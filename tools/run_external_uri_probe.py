"""Exercise cross-UID URI grant, FD decode, revocation and client-process restart.

Uses only the project-owned MP03 clip. Requires an exact installed current Debug
player and the conditionally built URI fixture APK. Stops the player process;
never clears player data. Results are device evidence only when run on a device.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.device_probe import Device, device_lock, output_directory

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_PACKAGE = "org.vrpassthroughplayer.urifixture"
FIXTURE_RECEIVER = FIXTURE_PACKAGE + "/.FixtureCommandReceiver"
URI = "content://org.vrpassthroughplayer.urifixture.documents/document/clip"


def validate_fixture(apk, expected_sha):
    with zipfile.ZipFile(apk) as archive:
        with archive.open("assets/mp03_frame_identity.mp4") as media:
            actual = hashlib.file_digest(media, "sha256").hexdigest()
    if actual != expected_sha:
        raise ValueError("Fixture APK contains different MP03 bytes")


def run_probe(device, fixture_apk, expected_sha, *, keep_fixture=False, timeout=90):
    """Run after verifying the player APK; always attempt grant cleanup."""
    validate_fixture(fixture_apk, expected_sha)
    result = {
        "state": "running",
        "steps": [],
        "scope": "Cross-UID read grant/revocation and native FD decode, including client-process restart; no picker UI, device reboot or Godot/XR acceptance",
    }
    installed = False
    failure = None
    client_uid = None

    def control(label, operation):
        nonlocal client_uid
        receipt = device.send_request(
            label,
            FIXTURE_PACKAGE + ".CONTROL",
            {"operation": operation},
            component=FIXTURE_RECEIVER,
            receipt_package=FIXTURE_PACKAGE,
            receipt_pattern="{key}.json",
            accepted=("applied",),
            track_process=False,
            include_stopped=True,
        )
        if receipt.get("uri") != URI or receipt.get("operation") != operation:
            raise RuntimeError("Fixture receipt has the wrong URI or operation")
        provider = receipt.get("provider_uid")
        client = receipt.get("client_uid")
        if type(provider) is not int or type(client) is not int or provider == client:
            raise RuntimeError("Fixture and player must have distinct UIDs")
        if receipt.get("clip_sha256") != expected_sha:
            raise RuntimeError("Provider clip does not match the bundled MP03 bytes")
        if client_uid is not None and client_uid != client:
            raise RuntimeError("Client UID changed during the run")
        client_uid = client
        result["client_uid"], result["provider_uid"] = client, provider
        result["steps"].append(
            {
                "step": label,
                "request": receipt["request"],
                "operation": operation,
                "provider_process": receipt.get("provider_process"),
            }
        )
        return receipt

    def decode(label, granted):
        receipt = device.send_request(
            label, device.package + ".DEBUG_MPV_URI", include_stopped=True
        )
        report = device.wait_report(
            label, receipt, f"mpv_uri_{receipt['id']}.json", timeout=timeout
        )
        if (
            report.get("uri") != URI
            or report.get("client_uid") != client_uid
            or report.get("fixture") != "mp03_frame_identity"
            or report.get("probe_kind") != "external_uri"
        ):
            raise RuntimeError("External FD report identity differs from the fixture")
        if report.get("descriptor_closed") is not True:
            raise RuntimeError("External probe did not confirm descriptor cleanup")
        if granted:
            if (
                report.get("state") != "passed"
                or report.get("permission_granted") is not True
                or report.get("descriptor_opened") is not True
            ):
                raise RuntimeError(
                    "Granted external URI did not complete native FD decode"
                )
        elif (
            report.get("state") != "failed"
            or report.get("permission_granted") is not False
            or report.get("descriptor_opened") is not False
            or report.get("error_type") != "permission_denied"
        ):
            raise RuntimeError(
                "Expected a real permission denial, not a decoder/open failure"
            )
        result["steps"].append(
            {
                "step": label,
                "request": receipt["request"],
                "diagnostic_process": receipt["diagnostic_process"],
                "access": "decoded" if granted else "permission_denied",
            }
        )
        return receipt["diagnostic_process"]

    try:
        device.run("install", "-r", str(fixture_apk))
        device.verify_apk(fixture_apk, package=FIXTURE_PACKAGE)
        installed = True
        control("restore", "restore")
        control("baseline-revoke", "revoke")
        device.run("shell", "am", "force-stop", device.package)
        device.process = None
        decode("before-grant", False)
        control("grant", "grant")
        decode("granted", True)
        control("revoke", "revoke")
        previous = decode("revoked", False)
        device.run("shell", "am", "force-stop", device.package)
        device.process = None
        restarted = decode("after-restart", False)
        if previous == restarted:
            raise RuntimeError(
                "Client process did not restart; evidence is inconclusive"
            )
        result["state"] = "passed"
    except BaseException as error:
        failure = error
        result.update(state="failed", error=str(error))
    finally:
        if installed:
            try:
                control("cleanup-revoke", "revoke")
                result["cleanup_revoked"] = True
            except Exception as error:
                result.update(
                    state="failed", cleanup_revoked=False, cleanup_error=str(error)
                )
                failure = failure or error
            if not keep_fixture:
                try:
                    removed = device.run("uninstall", FIXTURE_PACKAGE, optional=True)
                    result["fixture_uninstalled"] = "Success" in removed
                    if not result["fixture_uninstalled"]:
                        raise RuntimeError("Fixture uninstall failed")
                except Exception as error:
                    result.update(
                        state="failed",
                        fixture_uninstalled=False,
                        uninstall_error=str(error),
                    )
                    failure = failure or error
        device.save_json("result", result)
    if failure:
        raise failure
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--port", type=int, default=5037)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--fixture-apk", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--keep-fixture", action="store_true")
    parser.add_argument("--timeout", type=float, default=90)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    output = output_directory(args.output, "external-uri")
    device = Device(args.adb, args.serial, output, port=args.port)
    try:
        expected = json.loads(
            (ROOT / "tests/fixtures/mp03_frame_identity.json").read_text()
        )["sha256"]
        with device_lock(args.serial):
            device.verify_apk(args.apk)
            run_probe(
                device,
                args.fixture_apk,
                expected,
                keep_fixture=args.keep_fixture,
                timeout=args.timeout,
            )
    except (
        RuntimeError,
        TimeoutError,
        OSError,
        ValueError,
        KeyError,
        zipfile.BadZipFile,
    ) as error:
        device.save_json("failure", {"state": "failed", "error": str(error)})
        print(str(error), file=sys.stderr)
        return 1
    print(f"External URI evidence: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
