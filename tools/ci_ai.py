#!/usr/bin/env python3
"""Prepare a source-frame backend on macOS and transfer verified Android ELF files to Windows.

This keeps the release workflow at four build checks. Both AI hosts independently
prepare models/MNN and compile their Android plugin/APKs; only the target-platform
mpv/FFmpeg libraries are shared within the same workflow run.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

import build_player as player

ROOT = player.ROOT
CACHE = player.CACHE/'ci-ai/mpv'
LIBS = ('libmpv.so', 'libavcodec.so', 'libavdevice.so', 'libavfilter.so',
        'libavformat.so', 'libavutil.so', 'libswresample.so', 'libswscale.so')
BUNDLE = ROOT/'artifacts/ai-dependencies/mpv-source.zip'


def repository_inputs():
    paths = [ROOT/'tools/ci_ai.py', ROOT/'tools/environment/ai-player.lock.json',
             ROOT/'third_party/mpv/source-lock.json', ROOT/'tools/environment/mpv-linux/host-tools.lock.txt',
             ROOT/'native/mpv/include/mpv/quest_frame.h', ROOT/'native/mpv/include/mpv/quest_subtitle.h']
    paths += sorted((ROOT/'native/mpv/patches').glob('*.json'))
    paths += sorted((ROOT/'native/mpv/patches').glob('*.patch'))
    paths += sorted((ROOT/'tools/environment/mpv-linux').glob('*.py'))
    return {p.relative_to(ROOT).as_posix(): player.digest(p) for p in paths}


def verify_backend(directory=CACHE):
    directory = Path(directory)
    # The normal importer checks the exact frame/header/source contract and all bytes
    # before copying anything into the Android plugin's dependency directory.
    player.prepare_source_mpv(directory/'arm64-v8a', directory/'source-build.json')


def export_bundle(directory=CACHE, target=BUNDLE):
    directory, target = Path(directory), Path(target)
    verify_backend(directory)
    files = ['source-build.json', *['arm64-v8a/'+name for name in LIBS]]
    records = {name: dict(bytes=(directory/name).stat().st_size, sha256=player.digest(directory/name)) for name in files}
    metadata = dict(schema_version=1, inputs=repository_inputs(), files=records)
    target.parent.mkdir(parents=True, exist_ok=True)
    pending = target.with_suffix('.zip.pending')
    with zipfile.ZipFile(pending, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in files:
            archive.write(directory/name, name)
        archive.writestr('bundle-manifest.json', json.dumps(metadata, indent=2)+'\n')
    pending.replace(target)
    print('Prepared verified source-frame dependency bundle:', target, flush=True)


def import_bundle(source, destination=CACHE):
    destination = Path(destination)
    expected = {'source-build.json', *['arm64-v8a/'+name for name in LIBS]}
    with zipfile.ZipFile(source) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or set(names) != expected | {'bundle-manifest.json'}:
            raise RuntimeError('Unexpected/duplicate files in the source-frame dependency bundle')
        for info in archive.infolist():
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise RuntimeError('Source-frame dependency bundle contains a symlink')
        manifest = json.loads(archive.read('bundle-manifest.json'))
        if manifest.get('schema_version') != 1 or manifest.get('inputs') != repository_inputs() or set(manifest.get('files', {})) != expected:
            raise RuntimeError('Source-frame bundle belongs to different source/patch/tool inputs')
        # Stage and validate the complete bundle before publishing any selected files.
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mpv-import-', dir=destination.parent) as temporary:
            staged = Path(temporary)
            for name in expected:
                record = manifest['files'][name]
                data = archive.read(name)
                if len(data) != record['bytes'] or hashlib.sha256(data).hexdigest() != record['sha256']:
                    raise RuntimeError('Source-frame bundle hash/size differs: '+name)
                target = staged/name;target.parent.mkdir(parents=True, exist_ok=True);target.write_bytes(data)
            verify_backend(staged)
            destination.mkdir(parents=True, exist_ok=True)
            for name in expected:
                target = destination/name;target.parent.mkdir(parents=True, exist_ok=True)
                (staged/name).replace(target)
    print('Imported verified Android ARM64 source-frame dependencies', flush=True)


def cached_backend(inputs):
    stamp = CACHE/'inputs.json'
    if not stamp.is_file() or json.loads(stamp.read_text()) != inputs:
        return False
    try:
        verify_backend()
    except (RuntimeError, OSError, ValueError, KeyError):
        return False
    return True


def prepare_macos(jobs):
    if sys.platform != 'darwin':
        raise RuntimeError('Source-frame CI preparation runs on macOS; Windows imports its verified ARM64 bundle')
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise RuntimeError('Prepare the Android SDK before AI source-frame dependencies')
    ndk = Path(sdk)/'ndk'/player.LOCK['ndk']
    if not (ndk/'source.properties').is_file():
        raise RuntimeError('The locked Android NDK is missing')
    packages = subprocess.check_output(['brew', 'list', '--versions'], text=True)
    inputs = dict(repository=repository_inputs(), ndk_properties=player.digest(ndk/'source.properties'),
                  host_packages=hashlib.sha256(packages.encode()).hexdigest())
    if cached_backend(inputs):
        export_bundle();return
    work = player.CACHE/'ci-ai/mpv-work'
    downloads = player.CACHE/'ci-ai/mpv-downloads'
    work.mkdir(parents=True, exist_ok=True);downloads.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT/'tools/environment/ai-player.lock.json').read_text())
    for record in json.loads((ROOT/'third_party/mpv/source-lock.json').read_text())['sources']:
        archive = player.download(dict(url=record['url'], sha256=record['sha256']), record['archive'])
        target = downloads/record['archive']
        if not target.exists() or player.digest(target) != record['sha256']:
            shutil.copyfile(archive, target)
    record = lock['downloads']['mpv_builder']
    archive = player.download(record, record['filename'])
    if archive.stat().st_size != record['bytes']:
        raise RuntimeError('Pinned mpv builder archive size differs')
    builder = work/'mpv-android/buildscripts'
    if not builder.exists():
        with tarfile.open(archive) as source:
            source.extractall(work, filter='data')
        (work/('mpv-android-'+lock['mpv_builder_revision'])).rename(work/'mpv-android')
    # Reuse the SDK prepared by CI; no second NDK archive is needed.
    for link in (work/'android-ndk-r30', builder/'sdk/android-ndk-r30'):
        link.parent.mkdir(parents=True, exist_ok=True)
        if not link.exists():
            link.symlink_to(ndk, target_is_directory=True)
        if link.resolve() != ndk.resolve():
            raise RuntimeError('Cached mpv builder uses a different NDK')
    venv = work/'host-venv'
    if not (venv/'bin/python').exists():
        player.run([sys.executable, '-m', 'venv', venv])
    player.run([venv/'bin/python', '-m', 'pip', 'install', '--require-hashes', '-r',
                ROOT/'tools/environment/mpv-linux/host-tools.lock.txt'], log='ci-ai-mpv-python.log')
    player.run([venv/'bin/python', '-m', 'pip', 'install', *[f'{key}=={value}' for key,value in lock['mpv_host_python'].items()]],
               log='ci-ai-mpv-python-extra.log')
    prefix = Path(subprocess.check_output(['brew', '--prefix'], text=True).strip())
    path = [venv/'bin', prefix/'bin']
    for formula in ('gnu-sed', 'coreutils', 'findutils', 'gnu-tar'):
        path.append(Path(subprocess.check_output(['brew', '--prefix', formula], text=True).strip())/'libexec/gnubin')
    for formula in ('bison', 'flex', 'gettext'):
        path.append(Path(subprocess.check_output(['brew', '--prefix', formula], text=True).strip())/'bin')
    # Select GNU implementations before Darwin's tools, while retaining the venv Python.
    env = os.environ.copy();env['PATH'] = os.pathsep.join(map(str, path))+os.pathsep+env['PATH']
    toolchain = ndk/'toolchains/llvm/prebuilt/darwin-x86_64/bin'
    env.update(THRU3D_MPV_WORK=str(work), THRU3D_MPV_DOWNLOADS=str(downloads),
               THRU3D_MPV_TOOLCHAIN_BIN=str(toolchain), THRU3D_MPV_EXPORT=str(CACHE/'arm64-v8a'),
               THRU3D_MPV_MANIFEST=str(CACHE/'source-build.json'), THRU3D_TOOL_ROOT=str(work/'toolchain'), cores=str(jobs))
    (work/'host-packages.tsv').write_text(packages)
    player.run([venv/'bin/python', ROOT/'tools/environment/mpv-linux/prepare_sources.py'], env=env, log='ci-ai-mpv-sources.log')
    log = player.LOGS/'ci-ai-mpv-build.log'
    receipt = ROOT/'tools/environment/mpv-linux/build_receipt.py'
    player.run([venv/'bin/python', receipt, 'start', log], env=env)
    bash = Path(subprocess.check_output(['brew', '--prefix', 'bash'], text=True).strip())/'bin/bash'
    try:
        player.run([bash, builder/'buildall.sh', '--arch', 'arm64', 'mpv'], cwd=builder, env=env,
                   log=log.name, timeout=7200)
    except (RuntimeError, subprocess.TimeoutExpired):
        player.run([venv/'bin/python', receipt, 'fail', '1'], env=env)
        raise
    (ROOT/'build/output').mkdir(parents=True, exist_ok=True)
    player.run([venv/'bin/python', receipt, 'finish'], env=env)
    player.run([venv/'bin/python', ROOT/'tools/environment/mpv-linux/export_candidate.py'], env=env, log='ci-ai-mpv-export.log')
    if inputs != dict(repository=repository_inputs(), ndk_properties=player.digest(ndk/'source.properties'),
                      host_packages=hashlib.sha256(packages.encode()).hexdigest()):
        raise RuntimeError('AI source-frame preparation inputs changed during the build')
    (CACHE/'inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
    export_bundle()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    prepare = sub.add_parser('prepare-mpv');prepare.add_argument('--jobs', type=int, default=2)
    export = sub.add_parser('export-mpv');export.add_argument('--output', type=Path, default=BUNDLE)
    incoming = sub.add_parser('import-mpv');incoming.add_argument('--bundle', type=Path, default=BUNDLE)
    args = parser.parse_args()
    if args.command == 'prepare-mpv':
        if args.jobs < 1:parser.error('--jobs must be positive')
        prepare_macos(args.jobs)
    elif args.command == 'export-mpv':
        export_bundle(target=args.output)
    else:
        import_bundle(args.bundle)


if __name__ == '__main__':
    main()
