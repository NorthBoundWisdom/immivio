#!/usr/bin/env python3
"""Download/check public weights and prepare the model pack/MNN Android runtime.

All generated files stay in ignored directories. Source-frame mpv is built
separately through the recorded Linux workflow; this never substitutes standard
mpv for the AI player's verified source-frame backend.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

import build_player as builder

ROOT = builder.ROOT
CACHE = ROOT/'.cache/ai'
LOCK = json.loads((ROOT/'tools/environment/ai-player.lock.json').read_text())


def download(name):
    record = LOCK['downloads'][name]
    path = CACHE/'downloads'/record['filename']
    if not path.exists():
        downloaded = builder.download(record, record['filename'])
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(downloaded, path)
    if path.stat().st_size != record['bytes'] or builder.digest(path) != record['sha256']:
        raise RuntimeError('AI dependency/source differs from its pinned bytes: '+name)
    return path


def python_environment():
    executable = CACHE/'venv'/('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    if not executable.exists():
        builder.run([sys.executable, '-m', 'venv', CACHE/'venv'])
    builder.run([executable, '-m', 'pip', 'install', *[f'{name}=={version}' for name, version in LOCK['python'].items()]],
                log='ai-python-preparation.log')
    return executable


def prepare_models(python):
    for name, target in [('rvm', 'models/source/rvm_mobilenetv3_fp32.onnx'),
                         ('depth', 'models/source/depth/depth_anything_v2_small.onnx')]:
        path = ROOT/target
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and builder.digest(path) == LOCK['downloads'][name]['sha256']:
            continue
        downloaded = download(name)
        if not path.exists() or builder.digest(path) != LOCK['downloads'][name]['sha256']:
            shutil.copyfile(downloaded, path)
    # Conversion checks only; these generated inputs do not establish visual quality.
    samples = ROOT/'build/depth'
    samples.mkdir(parents=True, exist_ok=True)
    sample_script = '''from pathlib import Path
from PIL import Image, ImageDraw
root = Path('build/depth')
for i, name in enumerate(('sample_a.png', 'sample_b.png')):
    path = root/name
    if path.exists(): continue
    image = Image.new('RGB', (640, 360)); pixels = image.load()
    for y in range(360):
        for x in range(640): pixels[x,y] = (x*255//639, y*255//359, ((x//40+y//40+i)%2)*160+40)
    ImageDraw.Draw(image).ellipse((90+i*130,55,300+i*100,330), fill=(180,90,65))
    image.save(path)
'''
    builder.run([python, '-c', sample_script])
    env = os.environ.copy()
    env['MNNCONVERT'] = str(python.parent/('mnnconvert.exe' if os.name == 'nt' else 'mnnconvert'))
    builder.run([python, ROOT/'tools/models/specialize_rvm_ratio_one.py'], env=env, log='ai-rvm-specialization.log')
    builder.run([python, ROOT/'tools/models/prepare_rvm_mnn.py', '--variant', 'upstream'], env=env, log='ai-rvm-conversion.log')
    for extra, label in [([], 'video'), (['--photo'], 'photo')]:
        builder.run([python, ROOT/'tools/models/prepare_depth_mnn.py', '--install', *extra], env=env, log=f'ai-depth-{label}-conversion.log')
    builder.run([python, ROOT/'tools/model_assets.py', '--from-directory', ROOT/'android/player-plugin/src/main/assets',
                 '--record-converted', 'upstream'], log='ai-model-pack.log')
    builder.run([python, ROOT/'tools/model_assets.py', '--verify-only'])


def prepare_runtime(python, args):
    source = CACHE/'MNN-3.6.1'
    if not source.exists():
        with tarfile.open(download('mnn')) as archive:
            archive.extractall(CACHE, filter='data')
    fork = CACHE/'MNN-3.6.1-vrpp'
    native = CACHE/'mnn-android'
    ndk = args.sdk/'ndk'/args.ndk
    suffix = '.exe' if os.name == 'nt' else ''
    cmake = args.sdk/'cmake'/args.cmake/'bin'/('cmake'+suffix)
    ninja = cmake.with_name('ninja'+suffix)
    if not cmake.exists() or not (ndk/'build/cmake/android.toolchain.cmake').exists():
        raise RuntimeError('Install the selected Android NDK and CMake first')
    builder.run([python, ROOT/'tools/mnn/patch_mnn_vrpp.py', source, fork], log='ai-mnn-patch.log')
    options = ['-DANDROID_ABI=arm64-v8a', '-DANDROID_PLATFORM=android-26', '-DANDROID_STL=c++_shared',
               '-DCMAKE_BUILD_TYPE=Release', '-DMNN_BUILD_SHARED_LIBS=OFF', '-DMNN_SEP_BUILD=OFF', '-DMNN_OPENCL=ON',
               '-DMNN_VULKAN=OFF', '-DMNN_ARM82=ON', '-DMNN_USE_LOGCAT=ON', '-DMNN_BUILD_TOOLS=OFF',
               '-DMNN_BUILD_BENCHMARK=OFF', '-DMNN_BUILD_TEST=OFF', '-DMNN_BUILD_CONVERTER=OFF', '-DMNN_KLEIDIAI=OFF']
    builder.run([cmake, '-S', fork, '-B', native, '-G', 'Ninja', f'-DCMAKE_MAKE_PROGRAM={ninja}',
                 f'-DCMAKE_TOOLCHAIN_FILE={ndk}/build/cmake/android.toolchain.cmake', *options], log='ai-mnn-configure.log')
    builder.run([cmake, '--build', native, '--parallel', str(args.jobs)], log='ai-mnn-build.log')
    builder.extract(download('ncnn'), CACHE/'ncnn')
    receipt = dict(lock_sha256=builder.digest(ROOT/'tools/environment/ai-player.lock.json'),
                   patch_sha256=builder.digest(ROOT/'tools/mnn/patch_mnn_vrpp.py'), ndk=args.ndk, cmake=args.cmake,
                   mnn_library_sha256=builder.digest(native/'libMNN.a'), options=options)
    (CACHE/'native-preparation.json').write_text(json.dumps(receipt, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models-only', action='store_true')
    sdk_default = Path.home()/('Library/Android/sdk' if sys.platform == 'darwin' else 'Android/Sdk')
    if os.name == 'nt':
        sdk_default = Path(os.environ.get('LOCALAPPDATA', str(Path.home())))/'Android/Sdk'
    parser.add_argument('--sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME', str(sdk_default))))
    parser.add_argument('--ndk', default=builder.LOCK['ndk'])
    parser.add_argument('--cmake', default=builder.LOCK['cmake'])
    parser.add_argument('--jobs', type=int, default=8)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    CACHE.mkdir(parents=True, exist_ok=True)
    with builder.build_lock():
        python = python_environment()
        if not args.models_only:
            prepare_runtime(python, args)
        prepare_models(python)
    print('Public upstream model pack prepared. Source-frame mpv and device validation remain separate.')


if __name__ == '__main__':
    main()
