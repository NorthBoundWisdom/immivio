"""Verify the APK inspection gate and external playback rules using compiled-manifest fixtures."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from configs import player_build as builder

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


class ExportManifestGate(unittest.TestCase):
    # Representative aapt2 xmltree output, including namespace/resource IDs and typed booleans.
    @staticmethod
    def xmltree(binary_network=False, browsable=False):
        lines = [
            "N: android=http://schemas.android.com/apk/res/android (line=2)",
            "  E: manifest (line=2)",
            '    A: package="com.northboundwisdom.immivio" (Raw: "com.northboundwisdom.immivio")',
            "    E: application (line=3)",
            "      A: http://schemas.android.com/apk/res/android:appCategory(0x01010545)=2",
            "      A: android:isGame(0x010103f4)=false",
            "      E: activity (line=4)",
            '        A: android:name(0x01010003)="org.vrpassthroughplayer.plugin.ExternalPlaybackActivity" (Raw: "org.vrpassthroughplayer.plugin.ExternalPlaybackActivity")',
            "        A: android:exported(0x01010010)=(type 0x12)0xffffffff",
        ]
        groups = [("VIEW", ["http", "https"], ["video/*"] + (["application/octet-stream"] if binary_network else [])),
                  ("VIEW", ["content", "file"], ["video/*", "application/octet-stream"]),
                  ("SEND", [], ["video/*", "application/octet-stream"])]
        for action, schemes, mimes in groups:
            lines += ["        E: intent-filter (line=5)", "          E: action (line=6)",
                      f'            A: android:name(0x01010003)="android.intent.action.{action}" (Raw: "android.intent.action.{action}")',
                      "          E: category (line=7)",
                      '            A: android:name(0x01010003)="android.intent.category.DEFAULT" (Raw: "android.intent.category.DEFAULT")']
            if browsable and action == "VIEW":
                lines += ["          E: category (line=8)", '            A: android:name(0x01010003)="android.intent.category.BROWSABLE" (Raw: "android.intent.category.BROWSABLE")']
            for kind, values in [("scheme", schemes), ("mimeType", mimes)]:
                for value in values:
                    lines += ["          E: data (line=9)", f'            A: android:{kind}(0x01010000)="{value}" (Raw: "{value}")']
        return "\n".join(lines) + "\n"

    def test_apk_inspection_rejects_compiled_broad_filters_and_accepts_narrow_filters(self):
        # Mock native tools/signature checks only; execute the production APK inspection gate.
        for broad, browsable, unknown in [(False, False, False), (True, False, False), (False, True, False), (False, False, True)]:
            with self.subTest(broad=broad, browsable=browsable, unknown=unknown), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); logs = root / "logs"; logs.mkdir()
                apk = root / "fixture.apk"
                with zipfile.ZipFile(apk, "w") as archive:
                    for lib in ["libquest_media.so", "libquest_mpv.so", "libquest_render_bridge.so", "libgodot_android.so", "libmpv.so"]:
                        archive.writestr("lib/arm64-v8a/" + lib, b"fixture")
                tree = self.xmltree(broad, browsable) + ("unknown stdout record\n" if unknown else "")
                real_run = builder.run
                def run(_args, *, env, log, **kwargs):
                    if log == "base-apk-manifest.log":
                        (logs / log).write_text("package: name='com.northboundwisdom.immivio'\napplication-label:'Immivio'\n")
                    elif log == "base-apk-xmltree.log":
                        real_run([sys.executable, "-c", "import sys; sys.stdout.write(" + repr(tree) + "); sys.stderr.write('aapt2 warning on stderr\\n')"], cwd=root, log=log, **kwargs)
                with patch.object(builder, "ROOT", root), patch.object(builder, "LOGS", logs), \
                     patch.object(builder, "run", side_effect=run), \
                     patch.object(builder.subprocess, "check_output", return_value="AArch64\n LOAD fixture 0x4000\n"), \
                     patch.dict("os.environ", {"IMMIVIO_DEVELOPMENT_PACKAGE": "0"}):
                    if broad or browsable or unknown:
                        with self.assertRaisesRegex(RuntimeError, "manifest") as failure:
                            builder.inspect_package(apk, {"ANDROID_NDK_HOME": str(root / "ndk")}, root / "sdk")
                        self.assertIn("aapt2 warning on stderr", str(failure.exception))
                    else:
                        self.assertEqual(builder.digest(apk), builder.inspect_package(apk, {"ANDROID_NDK_HOME": str(root / "ndk")}, root / "sdk"))

    def test_compiled_decoder_preserves_typed_values_and_rejects_malformed_trees(self):
        tree = self.xmltree()
        root = manifest.verify_xmltree(tree)
        android = "{http://schemas.android.com/apk/res/android}"
        self.assertEqual(root.find("application").get(android + "appCategory"), "2")
        activity = root.find("application/activity")
        self.assertEqual(activity.get(android + "exported"), "true")
        self.assertEqual(len(activity.findall("intent-filter")), 3)
        for broken in [tree + "  E: manifest (line=50)\n",
                       tree + "garbage that must not be skipped\n",
                       tree.replace("(type 0x12)0xffffffff", "(type 0x12)0x0"),
                       tree.replace('A: android:isGame(0x010103f4)=false', 'A: android:isGame(0x010103f4)=false\n      A: android:isGame(0x010103f4)=true')]:
            with self.subTest(broken=broken[-80:]), self.assertRaises(ValueError):
                manifest.verify_xmltree(broken)


class SeparateToolStreams(unittest.TestCase):
    def test_failed_tool_preserves_and_surfaces_stderr(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, "LOGS", Path(directory)):
            with self.assertRaisesRegex(RuntimeError, "warning and failure"):
                builder.run([sys.executable, "-c", "import sys; print('stdout'); print('warning and failure', file=sys.stderr); sys.exit(2)"],
                            log="stdout.log", stderr_log="stderr.log")
            self.assertEqual((Path(directory) / "stdout.log").read_text(), "stdout\n")
            self.assertEqual((Path(directory) / "stderr.log").read_text(), "warning and failure\n")
