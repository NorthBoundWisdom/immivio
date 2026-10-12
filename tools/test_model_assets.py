"""Offline model-pack integrity, provenance and import regression tests."""
import copy
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

import model_assets as models


class ModelPacks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'
        self.destination = self.root / 'assets'
        self.pack = models.snapshot_pack()
        for model in self.pack['models']:
            path = self.source / model['path']
            path.parent.mkdir(parents=True, exist_ok=True)
            data = ('synthetic-' + model['task']).encode()
            path.write_bytes(data)
            model.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())

    def install(self):
        return models.install(self.pack, self.source, self.destination, prepare_support=False)

    def test_custom_model_has_its_own_identity_and_hash(self):
        self.pack['models'][0].update(id='my-student', version='experiment-2', source='local-training-run-2')
        selected = self.install()
        installed = models.read_json(self.destination / 'ai-models/manifest.json')
        self.assertEqual(installed, selected)
        self.assertEqual(installed['models'][0]['id'], 'my-student')
        models.verify_files(installed, self.destination)

    def test_custom_source_paths_are_normalized_to_adapter_assets(self):
        model = self.pack['models'][0]
        old = self.source / model['path']
        model['path'] = 'custom/student.mnn'
        target = self.source / model['path']
        target.parent.mkdir()
        old.rename(target)
        selected = self.install()
        self.assertEqual(selected['models'][0]['path'], 'rvm-mnn/rvm.mnn')
        self.assertFalse((self.destination / 'custom').exists())
        models.verify_files(selected, self.destination)

    def test_bad_final_model_does_not_replace_an_existing_pack(self):
        self.install()
        before = {p.relative_to(self.destination): p.read_bytes() for p in self.destination.rglob('*') if p.is_file()}
        self.pack['models'][0]['id'] = 'new-model'
        (self.source / self.pack['models'][-1]['path']).write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'size/hash'):
            self.install()
        after = {p.relative_to(self.destination): p.read_bytes() for p in self.destination.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def test_same_size_corruption_is_rejected(self):
        model = self.pack['models'][0]
        path = self.source / model['path']
        path.write_bytes(b'x' * model['bytes'])
        with self.assertRaisesRegex(ValueError, 'size/hash'):
            self.install()
        self.assertFalse(self.destination.exists())

    def test_paths_cannot_escape_the_model_pack(self):
        for path in ('../private.mnn', '/private.mnn', 'C:/private.mnn', 'foo\\private.mnn', 'foo/../private.mnn', './private.mnn'):
            with self.subTest(path=path):
                pack = copy.deepcopy(self.pack)
                pack['models'][0]['path'] = path
                with self.assertRaises(ValueError):
                    models.validate(pack)

    def test_symlink_outside_the_pack_is_rejected(self):
        model = self.pack['models'][0]
        path = self.source / model['path']
        outside = self.root / 'outside.mnn'
        path.rename(outside)
        try:
            path.symlink_to(outside)
        except OSError:
            self.skipTest('Host cannot create symlinks')
        with self.assertRaisesRegex(ValueError, 'outside pack'):
            models.verify_files(self.pack, self.source)

    def test_unknown_or_duplicate_tasks_and_contracts_fail(self):
        for field, value in (('task', 'speech'), ('task', 'video-depth'), ('adapter', 'generic-mnn'),
                             ('width', 320), ('width', False), ('bytes', True), ('sha256', '0' * 63), ('license', '')):
            with self.subTest(field=field, value=value):
                pack = copy.deepcopy(self.pack)
                pack['models'][0][field] = value
                with self.assertRaises(ValueError):
                    models.validate(pack)
        for field, value in (('schema_version', 2), ('schema_version', True), ('runtime', 'other-runtime')):
            pack = dict(self.pack, **{field: value})
            with self.assertRaises(ValueError):
                models.validate(pack)

    def prepare_conversion_manifests(self):
        reference = models.read_json(models.ROOT / 'models/manifest/runtime-assets.json')['manifests']
        for model in self.pack['models']:
            matting = model['task'] == 'matting'
            conversion = dict(mnn_sha256=model['sha256'], variant='upstream',
                              width=model['width'], height=model['height'],
                              source_sha256=reference['rvm-mnn' if matting else 'depth-mnn']['source_sha256'])
            path = self.source / model['path']
            name = 'photo_manifest.json' if model['task'] == 'photo-depth' else 'manifest.json'
            path.with_name(name).write_text(json.dumps(conversion))

    def test_recording_upstream_needs_no_private_student(self):
        self.prepare_conversion_manifests()
        recorded = models.from_converted(self.source, 'upstream')
        self.assertEqual(recorded['models'][0]['id'], 'rvm-mobilenetv3-upstream')
        self.assertEqual(recorded['models'][0]['license'], 'GPL-3.0')
        models.verify_files(recorded, self.source)

    def test_recorded_variant_and_provenance_must_match(self):
        self.prepare_conversion_manifests()
        with self.assertRaisesRegex(ValueError, 'variant'):
            models.from_converted(self.source, 'distilled')
        path = self.source / 'rvm-mnn/manifest.json'
        conversion = models.read_json(path)
        conversion['source_sha256'] = '0' * 64
        path.write_text(json.dumps(conversion))
        with self.assertRaisesRegex(ValueError, 'source'):
            models.from_converted(self.source, 'upstream')

    def test_snapshot_keeps_original_pins(self):
        snapshot = models.snapshot_pack()
        original = models.read_json(models.ROOT / 'models/manifest/runtime-assets.json')
        self.assertEqual([(m['path'], m['bytes'], m['sha256']) for m in snapshot['models']],
                         [(m['path'], m['bytes'], m['sha256']) for m in original['assets']])

    def converter(self):
        # Exercise actual CLI selection without requiring ONNX/MNN installations.
        # Graph mathematics are intentionally outside these offline boundary tests.
        fake_onnx = types.SimpleNamespace(load=lambda _: object(), save=lambda _, path: Path(path).write_bytes(b'graph'),
                                         checker=types.SimpleNamespace(check_model=lambda _: None))
        fake_fuse = types.SimpleNamespace(build=lambda **_: (object(), {'conv_hardswish': 20}), compare=lambda *_: {'pha': 0.0})
        path = models.ROOT / 'tools/models/prepare_rvm_mnn.py'
        spec = importlib.util.spec_from_file_location('rvm_conversion_test', path)
        module = importlib.util.module_from_spec(spec)
        with patch.dict('sys.modules', {'numpy': types.SimpleNamespace(), 'onnx': fake_onnx,
                                       'onnxruntime': types.SimpleNamespace(), 'fuse_rvm_graph': fake_fuse}):
            spec.loader.exec_module(module)
        module.ROOT = self.root
        module.SOURCE = self.root / 'source.onnx'
        module.SOURCE.write_bytes(b'pinned-specialized-source')
        module.OUT = self.root / 'converted'
        module.OUT.mkdir()
        module.STUDENT_MANIFEST = self.root / 'unavailable-private-student.json'
        module.PROFILES = [dict(key='320x320', width=320, height=320)]
        module.prune_fgr = lambda graph: graph
        module.add_u8_io = lambda graph: graph
        module.verify = lambda *_: 0.0
        module.verify_u8 = lambda *_: (0.0, 0.0)
        module.convert = lambda _, target: Path(target).write_bytes(b'converted-public-upstream')
        module.install = lambda: None
        return module

    def test_default_converter_replaces_a_cached_student_without_reading_private_weights(self):
        module = self.converter()
        (module.OUT / 'rvm.mnn').write_bytes(b'old-student')
        (module.OUT / 'manifest.json').write_text(json.dumps(dict(variant='distilled')))
        with patch('sys.argv', ['prepare_rvm_mnn.py']), contextlib.redirect_stdout(io.StringIO()):
            module.main()
        converted = models.read_json(module.OUT / 'manifest.json')
        self.assertEqual(converted['variant'], 'upstream')
        self.assertIsNone(converted['student'])
        self.assertEqual((module.OUT / 'rvm.mnn').read_bytes(), (module.OUT / 'rvm_quality.mnn').read_bytes())
        self.assertFalse(module.STUDENT_MANIFEST.exists())

    def test_converter_reuses_only_the_matching_variant(self):
        module = self.converter()
        (module.OUT / 'rvm.mnn').write_bytes(b'cached-public-model')
        (module.OUT / 'manifest.json').write_text(json.dumps(dict(variant='upstream')))
        installed = []
        module.install = lambda: installed.append(True)
        module.prune_fgr = lambda _: self.fail('Matching variant should reuse its verified conversion cache')
        with patch('sys.argv', ['prepare_rvm_mnn.py']):
            module.main()
        self.assertEqual(installed, [True])


if __name__ == '__main__':
    unittest.main()
