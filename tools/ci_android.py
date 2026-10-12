#!/usr/bin/env python3
"""Provision and exercise AI and model-free Android Release builders on hosted CI."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import quote
import xml.etree.ElementTree as ET
import zipfile

import build_player as player


def install_android_templates(record, destination):
    destination.mkdir(parents=True, exist_ok=True)
    if all((destination/name).is_file() and player.digest(destination/name) == sha
           for name, sha in record['files'].items()):
        return
    archive = player.download(record, 'godot-4.7.2-export-templates.tpz')
    with zipfile.ZipFile(archive) as source:
        # Only Android files are needed. Do not expand desktop/iOS templates.
        for name, sha in record['files'].items():
            data = source.read('templates/'+name)
            if hashlib.sha256(data).hexdigest() != sha:
                raise RuntimeError(f'Unexpected Godot Android template bytes: {name}')
            pending = destination/(name+'.pending')
            pending.write_bytes(data); pending.replace(destination/name)
    # Keep the verified Android subset in the cache, not the 1.2 GB multi-platform archive.
    archive.unlink()


def install_macos_fonts(executable):
    # Hosted macOS images can advertise unavailable on-demand Apple CJK fonts.
    # Supply the application's preferred Noto families without changing app UI code.
    directory = Path.home()/'Library/Fonts'
    directory.mkdir(parents=True, exist_ok=True)
    records = player.LOCK['ci']['macos_fonts']
    for record in records:
        source = player.download(record, record['filename'])
        shutil.copy2(source, directory/record['filename'])
    license_file = player.download(player.LOCK['ci']['macos_font_license'], 'NotoSansCJK-LICENSE.txt')
    shutil.copy2(license_file, directory/license_file.name)
    probe = player.ROOT/'build/ci_font_probe.gd'
    probe.parent.mkdir(parents=True, exist_ok=True)
    families = json.dumps([record['family'] for record in records])
    probe.write_text('extends SceneTree\nfunc _initialize():\n\tvar available = OS.get_system_fonts()\n'
        + '\tfor family in '+families+':\n\t\tif not family in available:\n'
        + '\t\t\tprinterr("Missing CI font: " + family)\n\t\t\tquit(1)\n\t\t\treturn\n'
        + '\tprint("CI_CJK_FONTS_READY")\n\tquit()\n', encoding='utf-8')
    player.LOGS.mkdir(parents=True, exist_ok=True)
    for attempt in range(10):
        try:
            result = subprocess.run([str(executable), '--headless', '--xr-mode', 'off', '--path', str(player.PROJECT),
                '--quit-after', '120', '--script', str(probe)],
                capture_output=True, text=True, encoding='utf-8', timeout=30)
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b'') + (error.stderr or b'')
            (player.LOGS/'ci-macos-fonts.log').write_bytes(output)
            raise RuntimeError('macOS font probe timed out; see artifacts/logs/ci-macos-fonts.log') from error
        (player.LOGS/'ci-macos-fonts.log').write_text(result.stdout+result.stderr, encoding='utf-8')
        if result.returncode == 0 and 'CI_CJK_FONTS_READY' in result.stdout:
            print('Registered pinned Noto CJK fonts for macOS host tests', flush=True)
            return
        if attempt < 9:
            time.sleep(1)
    raise RuntimeError('macOS did not register CI fonts; see artifacts/logs/ci-macos-fonts.log')


def setup():
    host = 'windows' if os.name == 'nt' else 'macos' if sys.platform == 'darwin' else None
    if not host:
        raise RuntimeError('This CI toolchain supports Windows and macOS')
    record = player.LOCK['ci']['godot']
    editor_record = record['editors'][host]
    editor = player.CACHE/'ci-tools/editor'
    archive = player.download(editor_record, f'godot-4.7.2-{host}.zip')
    player.extract(archive, editor)
    executable = editor/editor_record['executable']
    if os.name != 'nt':
        executable.chmod(0o755)
    observed = subprocess.check_output([str(executable), '--headless', '--version'], text=True).strip()
    if observed != record['version']:
        raise RuntimeError(f'Unexpected Godot engine version: {observed}')
    templates = player.CACHE/'ci-tools/templates/4.7.2.stable'
    install_android_templates(record['android_templates'], templates)
    if host == 'macos':
        install_macos_fonts(executable)
    sdk_path = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk_path:
        raise RuntimeError('ANDROID_HOME or ANDROID_SDK_ROOT must be set by Android setup')
    sdk = Path(sdk_path).absolute()
    on_path = shutil.which('sdkmanager') or shutil.which('sdkmanager.bat')
    manager = Path(on_path) if on_path else sdk/'cmdline-tools/latest/bin'/('sdkmanager.bat' if os.name == 'nt' else 'sdkmanager')
    if not manager.is_file():
        raise RuntimeError('Android command-line tools must be installed before CI setup')
    player.LOGS.mkdir(parents=True, exist_ok=True)
    with (player.LOGS/'ci-sdk-licenses.log').open('w', encoding='utf-8') as log:
        subprocess.run([str(manager), '--sdk_root='+str(sdk), '--licenses'], input='y\n'*100,
                       text=True, stdout=log, stderr=subprocess.STDOUT, check=True)
    player.run([manager, '--sdk_root='+str(sdk), 'platform-tools', 'platforms;android-36',
                'build-tools;36.1.0', 'ndk;'+player.LOCK['ndk'], 'cmake;'+player.LOCK['cmake']], log='ci-sdk-install.log')
    with Path(os.environ['GITHUB_ENV']).open('a', encoding='utf-8') as output:
        output.write(f'GODOT_EXE={executable}\nGODOT_TEMPLATES_DIR={templates}\n')
    print(f'Prepared {observed} and the locked Android SDK tools', flush=True)


def host_tests(godot):
    player.run([sys.executable, player.ROOT/'tools/Check-PublicSource.py'])
    player.run([sys.executable, player.ROOT/'tools/test_build_player.py'])
    player.run([sys.executable, player.ROOT/'tools/test_ci_android.py'])
    player.run([sys.executable, player.ROOT/'tools/test_ci_ai.py'])
    player.run([sys.executable, player.ROOT/'tools/test_model_assets.py'])
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if sdk:
        player.run([sys.executable, player.ROOT/'tools/test_ai_native_compat.py', '--ndk', Path(sdk)/'ndk'/player.LOCK['ndk']])
    logs = player.ROOT/'artifacts/source-tests'
    logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # Windows Godot honors these directories. Hosted macOS has fresh user state.
    userdata = player.ROOT/'artifacts/source-test-userdata'
    userdata.mkdir(parents=True, exist_ok=True)
    env.update(APPDATA=str(userdata), LOCALAPPDATA=str(userdata))
    player.run([godot, '--headless', '--xr-mode', 'off', '--path', player.PROJECT,
                '--editor', '--quit-after', '600'], env=env, log='ci-host-import.log')
    if re.search(r'(?m)^(SCRIPT ERROR:|SHADER ERROR:|ERROR:)', (player.LOGS/'ci-host-import.log').read_text(encoding='utf-8')):
        raise RuntimeError('Godot host import reported errors')
    suite = ET.Element('testsuite', name='Godot source tests')
    failures = []
    for script in sorted((player.PROJECT/'tests').glob('test_*.gd')):
        case = ET.SubElement(suite, 'testcase', name=script.stem)
        try:
            result = subprocess.run([godot, '--headless', '--xr-mode', 'off', '--path', str(player.PROJECT),
                '--quit-after', '1800', '--script', 'res://tests/'+script.name], env=env,
                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
            output = result.stdout+result.stderr
            (logs/(script.stem+'.log')).write_text(output, encoding='utf-8')
            if result.returncode or re.search(r'(?m)^(SCRIPT ERROR:|SHADER ERROR:|ERROR:)', output):
                raise RuntimeError(f'exit={result.returncode}; see {script.stem}.log')
            print('Passed: '+script.name, flush=True)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            failures.append(script.name)
            ET.SubElement(case, 'failure', message=str(error))
            print('Failed: '+script.name+': '+str(error), flush=True)
    suite.set('tests', str(len(suite))); suite.set('failures', str(len(failures)))
    ET.ElementTree(suite).write(logs/'junit.xml', encoding='utf-8', xml_declaration=True)
    if failures:
        raise RuntimeError(f'Godot source tests failed: {failures}')


def signing_env(environ):
    env = environ.copy()
    names = ('CI_ANDROID_KEYSTORE_BASE64', 'CI_ANDROID_KEY_ALIAS', 'CI_ANDROID_KEY_PASSWORD')
    values = [env.pop(name, '') for name in names]
    if not any(values):
        return env, 'ephemeral-ci-key'
    if not all(values):
        raise RuntimeError('Configure all three Android signing secrets, or none')
    key = Path(env.get('RUNNER_TEMP', player.ROOT/'artifacts/signing'))/'thru3d-ci-release.keystore'
    key.parent.mkdir(parents=True, exist_ok=True)
    key.write_bytes(base64.b64decode(values[0], validate=True))
    if os.name != 'nt':
        key.chmod(0o600)
    env.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(key), GODOT_ANDROID_KEYSTORE_RELEASE_USER=values[1],
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=values[2])
    return env, 'repository-signing-key'


def stop_gradle():
    suffix = 'gradle.bat' if os.name == 'nt' else 'gradle'
    shared = Path(os.environ.get('GRADLE_USER_HOME', Path.home()/'.gradle'))
    candidates = list((shared/'wrapper/dists').glob(f'gradle-{player.LOCK["gradle"]["version"]}-bin/*/gradle-*/bin/{suffix}'))
    candidates.append(player.CACHE/f'gradle/gradle-{player.LOCK["gradle"]["version"]}/bin/{suffix}')
    executable = next((path for path in candidates if path.is_file()), None)
    if executable:
        player.run([executable, '--stop'], log='ci-gradle-stop.log', timeout=60)
        print('Stopped Gradle daemons so Windows cache files can be archived', flush=True)
    else:
        print('No provisioned Gradle installation to stop', flush=True)


def check_export_path(templates, gradle, env):
    """Exercise the real template closure with Gradle, including Windows drive URIs."""
    directory = player.ROOT/'build/ci-export-path'
    directory.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(Path(templates)/'android_source.zip') as source:
        config = source.read('config.gradle').decode('utf-8')
    (directory/'config.gradle').write_text(player.patch_export_path(config), encoding='utf-8')
    (directory/'settings.gradle').write_text("rootProject.name = 'export-path-check'\n", encoding='utf-8')
    (directory/'marker.txt').write_bytes(b'export-path-check')
    (directory/'build.gradle').write_text("apply from: 'config.gradle'\n"
        + "tasks.register('checkExportPath', Copy) { from 'marker.txt'; into getExportPath() }\n", encoding='utf-8')
    destination = directory/'output with spaces+plus'
    shutil.rmtree(destination, ignore_errors=True)
    # Matches Godot's file:D:/... representation on Windows, retaining URI escaping.
    uri = 'file:'+quote(destination.absolute().as_posix(), safe='/:+')
    player.run([gradle, '-p', directory, '--console=plain', '-Pexport_path='+uri, 'checkExportPath'],
               env=env, log='ci-export-path-check.log', timeout=120)
    if (destination/'marker.txt').read_bytes() != b'export-path-check':
        raise RuntimeError('Gradle copied the export to an unexpected destination')
    print('Verified Godot/Gradle export path with spaces and a literal +', flush=True)


def build(vendor, godot, templates, *, ai=False):
    env, signing = signing_env(os.environ)
    vendors = ['Pico', 'Quest', 'OpenXR'] if vendor == 'all' else [vendor]
    receipts = []
    args = argparse.Namespace(vendor=vendors[0], build_type='Release', godot=godot, templates=Path(templates),
        sdk=None, java_home=None, gradle=None, ndk=player.LOCK['ndk'], cmake=player.LOCK['cmake'], plugin_only=False,
        ai=ai, mnn_source=player.CACHE/'ai/MNN-3.6.1-vrpp', mnn_lib=player.CACHE/'ai/mnn-android/libMNN.a',
        ncnn_dir=player.CACHE/'ai/ncnn/ncnn-20260526-android-vulkan/arm64-v8a',
        mpv_dir=player.CACHE/'ci-ai/mpv/arm64-v8a', mpv_receipt=player.CACHE/'ci-ai/mpv/source-build.json')
    # Keep a single lock and toolchain for all targets; reuse only within this invocation.
    with player.build_lock():
        env, sdk = player.environment(args, env)
        # Hosted CI uses the locked fallback; local reproductions may reuse a
        # deliberately configured shared installation through GRADLE_HOME.
        args.gradle = player.gradle_executable(args, use_host=os.environ.get('GITHUB_ACTIONS') != 'true')
        check_export_path(templates, args.gradle, env)
        player.prepare_dependencies(env, args)
        for index, target in enumerate(vendors):
            args.vendor = target
            started = time.monotonic()
            try:
                player.build(args, env, sdk, configure_editor=index == 0)
            finally:
                if player.LOGS.exists():
                    shutil.copytree(player.LOGS, player.ROOT/'artifacts/ci-logs'/target, dirs_exist_ok=True)
            platform = {'Pico': 'PICO', 'Quest': 'QUEST', 'OpenXR': 'OpenXR'}[target]
            mode = 'ai' if ai else 'noai'
            candidates = list((player.ROOT/'artifacts').glob(f'Thru3D-{platform}-*-{mode}-release-*.build.json'))
            if not candidates:
                raise RuntimeError('Missing receipt for the selected AI/build target')
            path = max(candidates, key=lambda p: p.stat().st_mtime)
            receipt = json.loads(path.read_text(encoding='utf-8'))
            if receipt.get('ai_enabled') is not ai:
                raise RuntimeError('Build receipt AI mode differs from the selected CI job')
            receipt.update(ci_signing=signing, ci_host=os.environ.get('RUNNER_OS', sys.platform),
                           ci_target_seconds=round(time.monotonic()-started, 1))
            path.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
            receipts.append(receipt)
            print(f'{target} build and verification: {receipt["ci_target_seconds"]}s', flush=True)
    artifacts = player.ROOT/'artifacts'
    (artifacts/'SHA256SUMS.txt').write_text(''.join(f'{r["sha256"]}  {r["apk"]}\n' for r in receipts), encoding='utf-8')
    (artifacts/'ci-summary.json').write_text(json.dumps(receipts, indent=2)+'\n', encoding='utf-8')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a', encoding='utf-8') as summary:
            summary.write(f'### Android Release, {"AI" if ai else "no AI"} — {os.environ.get("RUNNER_OS", sys.platform)}\n\n')
            contents = 'Public upstream models and the inference runtime are included.' if ai else 'CI packages contain no AI models or inference libraries.'
            summary.write(f'Signing: `{signing}`. {contents}\n\n')
            summary.write('| Platform | APK | SHA256 |\n|---|---|---|\n')
            for receipt in receipts:
                summary.write(f'| {receipt["vendor"]} | {receipt["apk"]} | `{receipt["sha256"]}` |\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('setup')
    commands.add_parser('stop-gradle')
    test = commands.add_parser('test')
    test.add_argument('--godot', default=os.environ.get('GODOT_EXE', 'godot'))
    package = commands.add_parser('build')
    package.add_argument('--vendor', choices=['all', 'Pico', 'Quest', 'OpenXR'], default=os.environ.get('CI_VENDOR', 'all'))
    package.add_argument('--godot', default=os.environ.get('GODOT_EXE', 'godot'))
    package.add_argument('--templates', default=os.environ.get('GODOT_TEMPLATES_DIR'))
    package.add_argument('--ai', action='store_true')
    args = parser.parse_args()
    if args.command == 'setup':
        setup()
    elif args.command == 'stop-gradle':
        stop_gradle()
    elif args.command == 'test':
        host_tests(args.godot)
    else:
        if not args.templates:
            parser.error('--templates or GODOT_TEMPLATES_DIR is required')
        build(args.vendor, args.godot, args.templates, ai=args.ai)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f'CI failed: {error}', file=sys.stderr)
        sys.exit(1)
