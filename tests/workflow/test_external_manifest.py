"""The actual exported manifest is checked by the same verifier used for these fixtures."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("external_manifest", ROOT / "tools/check_external_playback_manifest.py")
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)


class ExternalManifest(unittest.TestCase):
    def test_final_manifest_rejects_cartesian_network_binary_and_browsable_associations(self):
        def group(action, schemes, types, category="android.intent.category.DEFAULT"):
            return ('<intent-filter><action android:name="android.intent.action.' + action + '"/>'
                    '<category android:name="' + category + '"/>' +
                    ''.join('<data android:scheme="' + s + '"/>' for s in schemes) +
                    ''.join('<data android:mimeType="' + s + '"/>' for s in types) + '</intent-filter>')
        network = group("VIEW", ["http", "https"], ["video/*"])
        local = group("VIEW", ["content", "file"], ["video/*", "application/octet-stream"])
        send = group("SEND", [], ["video/*", "application/octet-stream"])
        header = '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application><activity android:name="' + manifest.ACTIVITY + '" android:exported="true">'
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "AndroidManifest.xml"
            for filters, valid in [(network + local + send, True),
                                   (group("VIEW", ["http", "https"], ["video/*", "application/octet-stream"]) + local + send, False),
                                   (network.replace('android.intent.category.DEFAULT', 'android.intent.category.BROWSABLE') + local + send, False)]:
                path.write_text(header + filters + '</activity></application></manifest>')
                if valid:
                    manifest.verify(path)
                else:
                    with self.assertRaises(ValueError):
                        manifest.verify(path)
