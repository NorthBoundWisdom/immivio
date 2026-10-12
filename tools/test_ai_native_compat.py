"""Check inference hashing can use Godot's existing C++ runtime without new exports.

This cross-compiles a tiny Android object; no models, MNN build or headset required.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def check(ndk):
    host = 'darwin-x86_64' if sys.platform == 'darwin' else 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
    toolchain = Path(ndk)/'toolchains/llvm/prebuilt'/host
    suffix = '.exe' if os.name == 'nt' else ''
    compiler, nm = toolchain/'bin'/('clang++'+suffix), toolchain/'bin'/('llvm-nm'+suffix)
    with tempfile.TemporaryDirectory(prefix='thru3d-libcxx-') as directory:
        source = Path(directory)/'probe.cpp'
        source.write_text('#include <functional>\n#include <string>\n'
            'extern "C" size_t probe(const char* p, size_t n) { return std::hash<std::string>{}(std::string(p,n)); }\n')
        results = {}
        for label, extra in [('baseline', []), ('compatible', ['-include', str(ROOT/'native/rvm/libcxx_compat.h')])]:
            output = source.with_suffix('.'+label+'.o')
            subprocess.run([str(compiler), '--target=aarch64-linux-android26', '--sysroot='+str(toolchain/'sysroot'),
                            '-std=c++17', '-O2', *extra, '-c', str(source), '-o', str(output)], check=True)
            undefined = subprocess.check_output([str(nm), '--undefined-only', str(output)], text=True)
            results[label] = '__hash_memory' in undefined
        if results['compatible']:
            raise RuntimeError('AI compatibility headers still require an unpackaged libc++ hash symbol')
    print('Android libc++ compatibility passed; baseline external hash_memory='+str(results['baseline']))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ndk', type=Path, default=Path(os.environ['ANDROID_NDK_HOME']) if os.environ.get('ANDROID_NDK_HOME') else None)
    args = parser.parse_args()
    if args.ndk is None:
        parser.error('--ndk or ANDROID_NDK_HOME is required')
    check(args.ndk)
