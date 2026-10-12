#!/usr/bin/env python3
"""Stage a build-selected model pack with explicit adapter contracts and pinned hashes.

Only metadata is committed. A custom pack manifest is an explicit build input, not
permission to substitute bytes under the snapshot's hashes. Runtime asset names
are normalized by the adapters; a build contains one model for each task.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'android/player-plugin/src/main/assets'
RUNTIME = 'mnn-3.6.1-vrpp-opencl-v1'
CONTRACTS = {
    'matting': ('rvm-rgba-recurrent-v1', 'rvm-mnn/rvm.mnn', 0, 0),
    'video-depth': ('relative-inverse-depth-v1', 'depth-mnn/depth.mnn', 252, 140),
    'photo-depth': ('relative-inverse-depth-v1', 'depth-mnn/photo_depth.mnn', 518, 518),
}


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def asset_path(value):
    if not isinstance(value, str) or not value or '\\' in value:
        raise ValueError('Model path must be a relative POSIX path')
    path = PurePosixPath(value)
    if path.is_absolute() or path.as_posix() != value or any(p in ('', '.', '..') for p in value.split('/')):
        raise ValueError('Model path must stay inside its pack')
    if any(':' in p for p in path.parts) or path.suffix != '.mnn':
        raise ValueError('Expected a relative .mnn model path')
    return value


def validate(pack):
    if not isinstance(pack, dict) or type(pack.get('schema_version')) is not int or pack.get('schema_version') != 1 or pack.get('runtime') != RUNTIME:
        raise ValueError('Unsupported model-pack schema or runtime ABI')
    models = pack.get('models')
    if not isinstance(models, list) or len(models) != len(CONTRACTS):
        raise ValueError('A pack requires one matting, video-depth and photo-depth model')
    tasks, ids, paths = set(), set(), set()
    for model in models:
        if not isinstance(model, dict):
            raise ValueError('Expected a model descriptor')
        task = model.get('task')
        if task not in CONTRACTS or task in tasks:
            raise ValueError('Unknown or duplicate model task')
        tasks.add(task)
        adapter, _, width, height = CONTRACTS[task]
        if model.get('adapter') != adapter or type(model.get('width')) is not int or type(model.get('height')) is not int or model.get('width') != width or model.get('height') != height:
            raise ValueError(f'Unsupported adapter or dimensions for {task}')
        for key in ('id', 'version', 'license', 'source'):
            value = model.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f'Model {task} requires {key}')
        if 'conversion' in model and not isinstance(model['conversion'], dict):
            raise ValueError('Conversion provenance must be an object')
        if model['id'] in ids:
            raise ValueError('Duplicate model ID')
        ids.add(model['id'])
        path = asset_path(model.get('path'))
        if path in paths:
            raise ValueError('A pack must use separate model files for each task')
        paths.add(path)
        size, sha = model.get('bytes'), model.get('sha256')
        if type(size) is not int or size <= 0 or not isinstance(sha, str) or len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha):
            raise ValueError(f'Invalid model size or SHA256 for {task}')
    return pack


def snapshot_pack():
    catalog = read_json(ROOT / 'models/manifest/runtime-assets.json')
    models = []
    for task, (adapter, path, width, height) in CONTRACTS.items():
        record = next(a for a in catalog['assets'] if a['path'] == path)
        rvm = task == 'matting'
        models.append(dict(record, task=task, adapter=adapter, width=width, height=height,
                           id='rvm-distilled-d1' if rvm else f'depth-anything-v2-small-{task}',
                           version='snapshot-1', license='GPL-3.0-derived' if rvm else 'Apache-2.0',
                           source='models/manifest/rvm_student.json' if rvm else 'https://huggingface.co/onnx-community/depth-anything-v2-small'))
    return validate(dict(schema_version=1, runtime=RUNTIME, models=models))


def verify_files(pack, directory):
    validate(pack)
    directory = Path(directory).resolve()
    for model in pack['models']:
        path = directory / model['path']
        if not path.resolve().is_relative_to(directory) or not path.is_file():
            raise ValueError(f'Missing model or path outside pack: {model["path"]}')
        if path.stat().st_size != model['bytes'] or digest(path) != model['sha256']:
            raise ValueError(f'Model size/hash differs: {model["path"]}')


def normalized(pack):
    return dict(pack, models=[dict(m, path=CONTRACTS[m['task']][1]) for m in pack['models']])


def validate_runtime_pack(pack):
    validate(pack)
    if normalized(pack) != pack:
        raise ValueError('Installed model paths differ from the runtime adapter assets; reimport the pack')
    return pack


def install(pack, source, destination=ASSETS, prepare_support=True, preserve_diagnostics=False):
    """Verify the complete source first; publish the runtime catalog last."""
    source, destination = Path(source).resolve(), Path(destination).resolve()
    verify_files(pack, source)
    destination.mkdir(parents=True, exist_ok=True)
    # Snapshot copies into a temporary directory before touching any current model.
    with tempfile.TemporaryDirectory(prefix='model-pack-', dir=destination.parent) as temporary:
        staged = Path(temporary)
        result = normalized(pack)
        for original, selected in zip(pack['models'], result['models']):
            path = staged / selected['path']
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / original['path'], path)
        verify_files(result, staged)
        for model in result['models']:
            target = destination / model['path']
            if not target.resolve().is_relative_to(destination):
                raise ValueError('Destination model path escapes asset directory')
            target.parent.mkdir(parents=True, exist_ok=True)
            (staged / model['path']).replace(target)
        metadata = destination / 'ai-models'
        metadata.mkdir(exist_ok=True)
        temporary_manifest = metadata / 'manifest.json.tmp'
        temporary_manifest.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        temporary_manifest.replace(metadata / 'manifest.json')
    # Compatibility metadata is consumed by existing diagnostics/build verification.
    for model in result['models']:
        name = 'photo_manifest.json' if model['task'] == 'photo-depth' else 'manifest.json'
        record = dict(model.get('conversion', {}), mnn_sha256=model['sha256'], model_id=model['id'], model_version=model['version'],
                      width=model['width'], height=model['height'], license=model['license'],
                      usage='photo' if model['task'] == 'photo-depth' else model['task'])
        (destination / model['path']).with_name(name).write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    if prepare_support:
        header = ROOT / 'build/rvm/include/rvm_profiles.generated.h'
        header.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'models/contracts/rvm_profiles.generated.h', header)
    for source_name, target_name in (
        ('RVM_GPL-3.0.txt', 'rvm/RVM_GPL-3.0.txt'),
        ('RVM_GPL-3.0.txt', 'rvm-mnn/RVM_GPL-3.0.txt'),
        ('DepthAnythingV2_Apache-2.0.txt', 'depth-mnn/LICENSE-DepthAnythingV2-Small.txt'),
    ):
        target = destination / target_name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'models/licenses' / source_name, target)
    license_file = destination / 'rvm/RVM_GPL-3.0.txt'
    bundle = license_file.parent / 'bundle_manifest.json'
    if not preserve_diagnostics or not bundle.exists():
        bundle.write_text(json.dumps({'assets': [dict(
            path='rvm/RVM_GPL-3.0.txt', bytes=license_file.stat().st_size, sha256=digest(license_file))]}, indent=2) + '\n')
    return result


def from_converted(directory, variant):
    """Record explicitly selected conversion outputs; never claim student equivalence."""
    directory = Path(directory)
    pack = snapshot_pack()
    for model in pack['models']:
        path = directory / model['path']
        name = 'photo_manifest.json' if model['task'] == 'photo-depth' else 'manifest.json'
        conversion = read_json(path.with_name(name))
        if conversion.get('mnn_sha256') != digest(path):
            raise ValueError('Conversion manifest does not match model bytes')
        if model['task'] == 'matting':
            reference = read_json(ROOT / 'models/manifest/runtime-assets.json')['manifests']['rvm-mnn']
            if conversion.get('variant', 'distilled') != variant or conversion.get('source_sha256') != reference['source_sha256']:
                raise ValueError('RVM variant or public source differs from the recorded conversion')
        else:
            reference = read_json(ROOT / 'models/manifest/runtime-assets.json')['manifests']['depth-mnn']
            if conversion.get('source_sha256') != reference['source_sha256'] or conversion.get('width') != model['width'] or conversion.get('height') != model['height']:
                raise ValueError('Depth source or shape differs from the recorded conversion')
        model['conversion'] = conversion
        model.update(bytes=path.stat().st_size, sha256=digest(path))
        if model['task'] != 'matting':
            model['version'] = 'public-conversion-v1'
        if model['task'] == 'matting':
            if variant == 'upstream':
                model.update(id='rvm-mobilenetv3-upstream', version='v1.0.0-ratio1-vrpp1', license='GPL-3.0',
                             source='https://github.com/PeterL1n/RobustVideoMatting/releases/tag/v1.0.0')
    return validate(pack)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-directory', type=Path)
    parser.add_argument('--manifest', type=Path, help='explicit trusted public/custom pack manifest; default: pinned snapshot')
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--record-converted', choices=('upstream', 'distilled'), help='record prepared conversion outputs as the selected pack')
    args = parser.parse_args()
    if args.record_converted:
        if args.manifest or args.verify_only or not args.from_directory:
            parser.error('--record-converted requires only --from-directory')
        pack = from_converted(args.from_directory, args.record_converted)
        install(pack, args.from_directory, destination=args.from_directory, preserve_diagnostics=True)
        output = args.from_directory / 'ai-models/manifest.json'
        print(output)
        return
    if args.verify_only:
        installed = validate_runtime_pack(read_json(ASSETS / 'ai-models/manifest.json'))
        verify_files(installed, ASSETS)
        if args.manifest:
            if normalized(validate(read_json(args.manifest))) != installed:
                raise ValueError('Installed model pack differs from the explicitly selected manifest')
        if digest(ROOT / 'build/rvm/include/rvm_profiles.generated.h') != digest(ROOT / 'models/contracts/rvm_profiles.generated.h'):
            raise ValueError('Native profile contract differs; reimport the model pack')
        print('Selected model pack verified.')
    else:
        if not args.from_directory:
            parser.error('--from-directory is required')
        pack = validate(read_json(args.manifest)) if args.manifest else snapshot_pack()
        install(pack, args.from_directory)
        print('Imported verified model pack; model weights remain ignored by Git.')


if __name__ == '__main__':
    main()
