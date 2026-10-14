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
            for name in ("used", "unimported"):
                module = "example.com/" + name
                version = "v1.0.0"
                record = proxy / module / "@v"
                record.mkdir(parents=True)
                mod = f"module {module}\n\ngo 1.20\n"
                (record / (version + ".mod")).write_text(mod)
                (record / (version + ".info")).write_text(
                    '{"Version":"v1.0.0","Time":"2020-01-01T00:00:00Z"}'
                )
                (record / "list").write_text(version + "\n")
                with zipfile.ZipFile(record / (version + ".zip"), "w") as archive:
                    archive.writestr(f"{module}@{version}/go.mod", mod)
                    archive.writestr(
                        f"{module}@{version}/value.go",
                        f"package {name}\nconst Value = 1\n",
                    )
            (source / "go.mod").write_text(
                "module example.com/fixture\n\ngo 1.20\n\nrequire (\n"
                " example.com/used v1.0.0\n example.com/unimported v1.0.0\n)\n"
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
                ["go", "mod", "download", "example.com/used"],
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
            shutil.rmtree(proxy)
            offline = dict(go_environment(env), GOOS="android", GOARCH="arm64")
            graph = subprocess.check_output(
                ["go", "list", "-m", "all"], cwd=source, env=offline, text=True
            )
            self.assertIn("example.com/unimported v1.0.0", graph)
            # gomobile may import packages that ordinary host package discovery skipped.
            packages = subprocess.check_output(
                ["go", "list", "example.com/unimported"],
                cwd=source,
                env=offline,
                text=True,
            )
            self.assertEqual(packages.strip(), "example.com/unimported")
