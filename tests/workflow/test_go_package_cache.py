"""A cold module cache must support gomobile's offline module-graph lookup."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from configs import android_workflow as android, player_build as player
from configs.dependencies import go_environment


@unittest.skipUnless(
    shutil.which("go"), "Go is required for the module-cache regression"
)
class GoPackageCache(unittest.TestCase):
    def test_preparation_caches_modules_outside_the_imported_package_graph(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            proxy, source = root / "proxy", root / "source"
            source.mkdir()
            records = [
                ("leaf", "v1.0.0", "", "package leaf\nconst Value = 1\n"),
                ("leaf", "v1.1.0", "", "package leaf\nconst Value = 2\n"),
                (
                    "unimported",
                    "v1.0.0",
                    "require example.com/leaf v1.1.0\n",
                    "package unimported\n",
                ),
                (
                    "used",
                    "v1.0.0",
                    "require (\nexample.com/leaf v1.0.0\nexample.com/unimported v1.0.0\n)\n",
                    'package used\nimport "example.com/leaf"\nvar Value = leaf.Value\n',
                ),
            ]
            for name, version, dependencies, code in records:
                module = "example.com/" + name
                record = proxy / module / "@v"
                record.mkdir(parents=True, exist_ok=True)
                mod = f"module {module}\n\ngo 1.20\n\n{dependencies}"
                (record / (version + ".mod")).write_text(mod)
                (record / (version + ".info")).write_text(
                    '{"Version":"' + version + '","Time":"2020-01-01T00:00:00Z"}'
                )
                with (record / "list").open("a") as versions:
                    versions.write(version + "\n")
                with zipfile.ZipFile(record / (version + ".zip"), "w") as archive:
                    archive.writestr(f"{module}@{version}/go.mod", mod)
                    archive.writestr(f"{module}@{version}/value.go", code)
            (source / "go.mod").write_text(
                "module example.com/fixture\n\ngo 1.20\n\nrequire (\n"
                " example.com/used v1.0.0\n example.com/leaf v1.0.0 // indirect\n)\n"
            )
            (source / "fixture.go").write_text(
                'package fixture\nimport "example.com/used"\nvar Value = used.Value\n'
            )
            env = dict(
                os.environ,
                GOPATH=str(root / "gopath"),
                GOMODCACHE=str(root / "modules"),
                GOCACHE=str(root / "cache"),
                GOPROXY=proxy.as_uri(),
                GOSUMDB="off",
                GOWORK="off",
                GOPRIVATE="",
                GONOPROXY="",
                GONOSUMDB="",
            )
            (source / "cloudcore").mkdir()
            (source / "fixture.go").rename(source / "cloudcore/fixture.go")
            online = go_environment(env, online=True)
            subprocess.run(
                ["go", "mod", "download", "example.com/used", "example.com/leaf"],
                cwd=source,
                env=online,
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["go", "list", "-deps", "-test", "./cloudcore"],
                cwd=source,
                env=online,
                check=True,
                capture_output=True,
            )
            incomplete = subprocess.run(
                ["go", "list", "-m", "all"],
                cwd=source,
                env=go_environment(env),
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(
                incomplete.returncode,
                0,
                "Package discovery must reproduce the cold-cache gap",
            )
            with patch.object(player, "LOGS", root / "logs"):
                android.prepare_go_packages(source, env)
            self.assertEqual(
                (source / "go.mod")
                .read_text()
                .split("example.com/leaf ")[1]
                .split()[0],
                "v1.0.0",
            )
            shutil.rmtree(proxy)
            offline = dict(go_environment(env), GOOS="android", GOARCH="arm64")
            graph = subprocess.check_output(
                ["go", "list", "-m", "all"], cwd=source, env=offline, text=True
            )
            self.assertIn("example.com/unimported v1.0.0", graph)
            # Promoting an otherwise unused module to a root requirement changes
            # MVS: gomobile's tidy selects leaf v1.1.0, not the app's leaf v1.0.0.
            binding = source.parent / "openlist-binding-modules"
            (binding / "wrapper.go").write_text(
                'package gobind\nimport _ "example.com/fixture/cloudcore"\n'
            )
            subprocess.run(
                ["go", "mod", "tidy"],
                cwd=binding,
                env=offline,
                check=True,
                capture_output=True,
                text=True,
            )
            selected = subprocess.check_output(
                ["go", "list", "-m", "example.com/leaf"],
                cwd=binding,
                env=offline,
                text=True,
            )
            self.assertEqual(selected.strip(), "example.com/leaf v1.1.0")
