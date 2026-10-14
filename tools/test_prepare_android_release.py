import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import prepare_android_release as release
import select_android_release as selection

TAG = "v0.6.0-fork.1"
COMMIT = "a" * 40


class ReleaseAssets(unittest.TestCase):
    def fixture(self, root):
        directory = root / "packages"
        directory.mkdir()
        for vendor, platform in release.PLATFORMS.items():
            name = f"Immivio-{platform}-0.6.0-release-20261013.apk"
            data = vendor.encode()
            (directory / name).write_bytes(data)
            record = {
                "schema_version": 2,
                "dependency_mode": "pinned",
                "freecm_commit": "d" * 40,
                "dependency_commits": {"OpenList": "e" * 40},
                "dependency_assets": {"OpenXRVendors": []},
                "gradle_locks": {"android/gradle.lockfile": "f" * 64},
                "dependency_manifests": {
                    key: "f" * 64
                    for key in (
                        "source_roots.lock.jsonc.in",
                        "configs/toolchain.json",
                        "android/gradle/libs.versions.toml",
                        "android/gradle/verification-metadata.xml",
                        "cloud/openlist/go.mod",
                        "cloud/openlist/go.sum",
                    )
                },
                "vendor": vendor,
                "apk": name,
                "sha256": hashlib.sha256(data).hexdigest(),
                "product": "Immivio",
                "build_type": "Release",
                "source_commit": COMMIT,
                "ci_ref": "refs/tags/" + TAG,
                "ci_host": "macOS",
                "signing_certificate_sha256": "b" * 64,
                "ci_signing": "ephemeral-ci-key",
            }
            (directory / Path(name).with_suffix(".build.json")).write_text(
                json.dumps(record)
            )
        return directory

    def test_complete_tag_build_prepares_three_apks_receipts_hashes_and_notes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            packages = self.fixture(root)
            output = root / "release"
            manifest = release.prepare(packages, output, TAG, COMMIT)
            self.assertEqual(len(list(output.glob("*.apk"))), 3)
            self.assertEqual(len(list(output.glob("*.build.json"))), 3)
            self.assertEqual(manifest["source_commit"], COMMIT)
            for line in (output / "SHA256SUMS.txt").read_text().splitlines():
                digest, name = line.split("  ")
                self.assertEqual(release.sha256(output / name), digest)
            self.assertIn("different key", (output / "release-notes.md").read_text())
            self.assertEqual(
                json.loads((output / "release-manifest.json").read_text()), manifest
            )

    def test_wrong_tag_commit_host_mode_and_debug_packages_cannot_publish(self):
        for key, value in [
            ("source_commit", "c" * 40),
            ("ci_ref", "refs/heads/main"),
            ("ci_host", "Windows"),
            ("product", "Other"),
            ("build_type", "Debug"),
            ("signing_certificate_sha256", ""),
        ]:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                packages = self.fixture(root)
                receipt = sorted(packages.glob("*.build.json"))[-1]
                record = json.loads(receipt.read_text())
                record[key] = value
                receipt.write_text(json.dumps(record))
                with self.assertRaises(ValueError):
                    release.prepare(packages, root / "release", TAG, COMMIT)
                self.assertFalse((root / "release").exists())

    def test_receipts_without_optional_certificate_metadata_remain_publishable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            packages = self.fixture(root)
            for receipt in packages.glob("*.build.json"):
                record = json.loads(receipt.read_text())
                del record["signing_certificate_sha256"]
                receipt.write_text(json.dumps(record))
            manifest = release.prepare(packages, root / "release", TAG, COMMIT)
            self.assertEqual(len(manifest["packages"]), 3)
            self.assertNotIn("signing_certificate_sha256", manifest["packages"][0])

    def test_unpinned_or_incomplete_dependency_provenance_is_rejected(self):
        for key, value in [
            ("dependency_mode", "latest"),
            ("schema_version", 1),
            ("freecm_commit", ""),
            ("dependency_manifests", {}),
            ("gradle_locks", {}),
        ]:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                packages = self.fixture(root)
                receipt = next(packages.glob("*.build.json"))
                record = json.loads(receipt.read_text())
                record[key] = value
                receipt.write_text(json.dumps(record))
                with self.assertRaises(ValueError):
                    release.prepare(packages, root / "release", TAG, COMMIT)
                self.assertFalse((root / "release").exists())

    def test_corrupt_late_apk_does_not_copy_any_other_valid_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            packages = self.fixture(root)
            sorted(packages.glob("*.apk"))[-1].write_bytes(b"corrupted")
            with self.assertRaisesRegex(ValueError, "differs"):
                release.prepare(packages, root / "release", TAG, COMMIT)
            self.assertFalse((root / "release").exists())

    def test_incomplete_or_extra_packages_are_rejected(self):
        for extra in [False, True]:
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                packages = self.fixture(root)
                if extra:
                    (packages / "unverified.apk").write_bytes(b"extra")
                else:
                    next(packages.glob("*.build.json")).unlink()
                with self.assertRaises(ValueError):
                    release.prepare(packages, root / "release", TAG, COMMIT)
                self.assertFalse((root / "release").exists())

    def test_apk_path_cannot_escape_input_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            packages = self.fixture(root)
            receipt = next(packages.glob("*.build.json"))
            record = json.loads(receipt.read_text())
            record["apk"] = "../outside.apk"
            receipt.write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, "filename"):
                release.prepare(packages, root / "release", TAG, COMMIT)
            self.assertFalse((root / "release").exists())


class ReleaseSource(unittest.TestCase):
    def fixture(self):
        run = {
            "id": 123,
            "head_repository": {"full_name": "owner/player"},
            "event": "push",
            "head_branch": TAG,
            "head_sha": COMMIT,
            "path": ".github/workflows/android-release.yml",
            "status": "completed",
            "conclusion": "success",
        }
        jobs = [
            {"name": name, "conclusion": "success"} for name in selection.BUILD_JOBS
        ]
        return run, jobs

    def test_successful_historical_tag_run_can_be_backfilled(self):
        run, jobs = self.fixture()
        self.assertEqual(
            selection.validate("owner/player", TAG, run, COMMIT, jobs), COMMIT
        )

    def test_previous_hosted_jobs_remain_valid_for_historical_tags(self):
        run, _ = self.fixture()
        jobs = [
            {"name": name, "conclusion": "success"}
            for name in selection.LEGACY_BUILD_JOBS
        ]
        self.assertEqual(
            selection.validate("owner/player", TAG, run, COMMIT, jobs), COMMIT
        )

    def test_mixed_old_and_new_host_names_cannot_replace_a_complete_matrix(self):
        run, _ = self.fixture()
        jobs = [
            {"name": "Release / Windows", "conclusion": "success"},
            {"name": "Release / macos-15", "conclusion": "success"},
        ]
        with self.assertRaises(ValueError):
            selection.validate("owner/player", TAG, run, COMMIT, jobs)

    def test_automatic_publisher_requires_passed_builds_in_its_current_run(self):
        run, jobs = self.fixture()
        run.update(status="in_progress", conclusion=None)
        self.assertEqual(
            selection.validate("owner/player", TAG, run, COMMIT, jobs, "123"), COMMIT
        )
        with self.assertRaises(ValueError):
            selection.validate("owner/player", TAG, run, COMMIT, jobs, "456")

    def test_failed_skipped_or_missing_builds_cannot_publish(self):
        for result in ["failure", "skipped", None]:
            with self.subTest(result=result):
                run, jobs = self.fixture()
                jobs[0]["conclusion"] = result
                with self.assertRaises(ValueError):
                    selection.validate("owner/player", TAG, run, COMMIT, jobs)
        run, jobs = self.fixture()
        with self.assertRaises(ValueError):
            selection.validate("owner/player", TAG, run, COMMIT, jobs[:-1])

    def test_branch_pr_wrong_commit_and_other_workflow_cannot_publish(self):
        for key, value in [
            ("head_branch", "main"),
            ("event", "pull_request"),
            ("head_sha", "b" * 40),
            ("path", ".github/workflows/other.yml"),
            ("head_repository", {"full_name": "other/player"}),
            ("conclusion", "failure"),
        ]:
            with self.subTest(key=key):
                run, jobs = self.fixture()
                run[key] = value
                with self.assertRaises(ValueError):
                    selection.validate("owner/player", TAG, run, COMMIT, jobs)


if __name__ == "__main__":
    unittest.main()
