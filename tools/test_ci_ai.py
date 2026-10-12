"""Offline integrity tests for the dependency bundle shared by the two AI jobs."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import ci_ai as ci


class AiBundleBoundaries(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory();self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root/'source';(self.source/'arm64-v8a').mkdir(parents=True)
        for name in ci.LIBS:
            (self.source/'arm64-v8a'/name).write_bytes(('synthetic-'+name).encode())
        (self.source/'source-build.json').write_text('{"candidate":"source-frame"}')
        self.bundle = self.root/'bundle.zip'
        self.destination = self.root/'imported'
        self.inputs = patch.object(ci, 'repository_inputs', return_value={'recipe':'fixture'}).start()
        self.addCleanup(patch.stopall)
        self.verify = patch.object(ci, 'verify_backend').start()
        ci.export_bundle(self.source, self.bundle)
        self.verify.reset_mock()

    def rewrite(self, change):
        with zipfile.ZipFile(self.bundle) as z:
            data = {name:z.read(name) for name in z.namelist()}
        change(data)
        with zipfile.ZipFile(self.bundle, 'w') as z:
            for name, value in data.items():z.writestr(name, value)

    def test_imports_exactly_the_verified_target_platform_libraries(self):
        ci.import_bundle(self.bundle, self.destination)
        self.verify.assert_called_once()
        for name in ci.LIBS:
            self.assertEqual((self.destination/'arm64-v8a'/name).read_bytes(), (self.source/'arm64-v8a'/name).read_bytes())
        self.assertEqual((self.destination/'source-build.json').read_bytes(), (self.source/'source-build.json').read_bytes())

    def test_corruption_fails_before_replacing_an_existing_selection(self):
        self.destination.mkdir();sentinel = self.destination/'source-build.json';sentinel.write_bytes(b'existing')
        self.rewrite(lambda data:data.update({'arm64-v8a/libmpv.so':b'corrupt'}))
        with self.assertRaisesRegex(RuntimeError, 'hash/size'):
            ci.import_bundle(self.bundle, self.destination)
        self.verify.assert_not_called()
        self.assertEqual(sentinel.read_bytes(), b'existing')
        self.assertFalse((self.destination/'arm64-v8a').exists())

    def test_other_recipe_cannot_supply_the_windows_ai_backend(self):
        def change(data):
            metadata = json.loads(data['bundle-manifest.json']);metadata['inputs'] = {'recipe':'different'}
            data['bundle-manifest.json'] = json.dumps(metadata).encode()
        self.rewrite(change)
        with self.assertRaisesRegex(RuntimeError, 'different source'):
            ci.import_bundle(self.bundle, self.destination)
        self.verify.assert_not_called()

    def test_missing_and_escaping_entries_are_rejected(self):
        self.rewrite(lambda data:data.update({'../outside.so':b'outside'}))
        with self.assertRaisesRegex(RuntimeError, 'Unexpected'):
            ci.import_bundle(self.bundle, self.destination)
        self.assertFalse((self.root/'outside.so').exists())
        self.assertFalse(self.destination.exists())

    def test_symlink_payload_is_rejected(self):
        with zipfile.ZipFile(self.bundle) as z:data = {name:z.read(name) for name in z.namelist()}
        with zipfile.ZipFile(self.bundle, 'w') as z:
            for name,value in data.items():
                info = zipfile.ZipInfo(name)
                if name == 'arm64-v8a/libmpv.so':info.external_attr = 0o120777 << 16
                z.writestr(info,value)
        with self.assertRaisesRegex(RuntimeError, 'symlink'):
            ci.import_bundle(self.bundle, self.destination)

    def test_failed_source_frame_contract_never_publishes_the_bundle(self):
        self.verify.side_effect = RuntimeError('incorrect frame ABI')
        with self.assertRaisesRegex(RuntimeError, 'frame ABI'):
            ci.import_bundle(self.bundle, self.destination)
        self.assertFalse(self.destination.exists())


if __name__ == '__main__':
    unittest.main()
