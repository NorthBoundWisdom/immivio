"""PICO 4/Neo3/4 Ultra store APK checks, separate from platform review/approval."""

import hashlib
import re
from pathlib import Path
import zipfile

from configs.android_manifest import ANDROID

DOCUMENT = "https://developer-cn.picoxr.com/document/distribute/app-publish-first-version/#3af79c21"
# Conservative decimal limit also remains below a 4-GiB upload ceiling.
MAX_APK_BYTES = 4_000_000_000
PACKAGE = "com.northboundwisdom.immivio"
# Public certificate fingerprint of the project-owned PICO store key.
# Keep this identity stable after the first PICO store upload; never store key bytes here.
CERTIFICATE_SHA256 = "89b2a063d2783d04971415ccc1d98eb47eefd7fd343e242a61931a22f786d89b"
IMMERSIVE = "org.khronos.openxr.intent.category.IMMERSIVE_HMD"
DEBUG_COMPONENTS = {
    "org.vrpassthroughplayer.plugin.DebugDiagnosticsReceiver",
    "org.vrpassthroughplayer.plugin.MpvDiagnosticActivity",
}


def _integer(value, label):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+", value):
        raise ValueError(f"PICO store: invalid {label}")
    return int(value)


def validate(
    apk,
    manifest,
    *,
    certificate,
    expected_certificate,
    version,
    version_code,
    expected_app_id=None,
    baseline=None,
):
    """Inspect actual compiled output, not just source presets.

    An optional baseline must describe an already uploaded version in the same
    PICO track/region. A locally built package is not an upload baseline.
    """
    apk = Path(apk)
    size = apk.stat().st_size
    if apk.suffix.lower() != ".apk" or not 0 < size <= MAX_APK_BYTES:
        raise ValueError("PICO store: expected a nonempty APK no larger than 4 GB")
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        if not {"AndroidManifest.xml", "classes.dex", "assets/project.binary"} <= names:
            raise ValueError("PICO store: APK is missing its base application payload")
        libraries = {
            n.split("/")[1] for n in names if n.startswith("lib/") and n.endswith(".so")
        }
        if libraries != {"arm64-v8a"}:
            raise ValueError("PICO store: only ARM64 libraries are permitted")
        features = archive.read("assets/project.binary")
        if b"immivio_appstore" not in features or b"immivio_web" in features:
            raise ValueError("PICO store: package must use the appstore channel")
    if (
        manifest.get("package") != PACKAGE
        or manifest.get("split")
        or manifest.findall("uses-split")
    ):
        raise ValueError(
            "PICO store: expected the existing Immivio package as a standalone APK"
        )
    if manifest.get(ANDROID + "sharedUserId"):
        raise ValueError(
            "PICO store: sharedUserId is not permitted by this store profile"
        )
    actual_code = _integer(manifest.get(ANDROID + "versionCode"), "versionCode")
    actual_version = manifest.get(ANDROID + "versionName")
    if actual_code < 1 or actual_code != version_code or actual_version != version:
        raise ValueError("PICO store: APK version differs from the release presets")
    sdk = manifest.find("uses-sdk")
    if sdk is None:
        raise ValueError("PICO store: missing uses-sdk")
    minimum = _integer(sdk.get(ANDROID + "minSdkVersion"), "minSdkVersion")
    target = _integer(sdk.get(ANDROID + "targetSdkVersion"), "targetSdkVersion")
    compile_sdk = _integer(
        manifest.get(ANDROID + "compileSdkVersion"), "compileSdkVersion"
    )
    if not 1 <= minimum <= 29 or not 23 <= target <= compile_sdk or minimum > target:
        raise ValueError(
            "PICO store: PICO 4/Neo3 require minSdkVersion <=29 and valid target/compile SDKs"
        )
    application = manifest.find("application")
    if application is None:
        raise ValueError("PICO store: missing application")
    if any(
        application.get(ANDROID + flag, "false") != "false"
        for flag in ("debuggable", "testOnly")
    ):
        raise ValueError("PICO store: Debug/testOnly packages cannot be submitted")
    if any(node.get(ANDROID + "name") in DEBUG_COMPONENTS for node in application):
        raise ValueError("PICO store: diagnostic components cannot be submitted")
    if (
        not re.fullmatch(r"[0-9a-f]{64}", certificate or "")
        or certificate != expected_certificate
    ):
        raise ValueError(
            "PICO store: APK signer differs from the configured release key"
        )
    metadata = {}
    for node in application.findall("meta-data"):
        name = node.get(ANDROID + "name")
        if name in metadata:
            raise ValueError("PICO store: duplicate application metadata")
        metadata[name] = node.get(ANDROID + "value", "")
    if not manifest.findall(f".//category[@{ANDROID}name='{IMMERSIVE}']"):
        raise ValueError("PICO store: missing OpenXR immersive entry")
    if not metadata.get("pvr.sdk.version") and not metadata.get("pxr.sdk.version_code"):
        raise ValueError(
            "PICO store: OpenXR APK must declare its actual PICO SDK version"
        )
    if metadata.get("pxr.sdk.version_code"):
        _integer(metadata["pxr.sdk.version_code"], "pxr.sdk.version_code")
    app_id = metadata.get("pvr.app.id")
    if app_id is not None and (not expected_app_id or app_id != expected_app_id):
        raise ValueError(
            "PICO store: pvr.app.id requires the matching IMMIVIO_PICO_APP_ID"
        )
    launchers = []
    for node in list(application.findall("activity")) + list(
        application.findall("activity-alias")
    ):
        for group in node.findall("intent-filter"):
            actions = {item.get(ANDROID + "name") for item in group.findall("action")}
            categories = {
                item.get(ANDROID + "name") for item in group.findall("category")
            }
            if (
                "android.intent.action.MAIN" in actions
                and "android.intent.category.LAUNCHER" in categories
            ):
                if node.get(ANDROID + "exported") != "true":
                    raise ValueError("PICO store: launcher must be exported")
                launchers.append(node.get(ANDROID + "name"))
    if len(launchers) != 1:
        raise ValueError("PICO store: expected exactly one launcher icon")
    with apk.open("rb") as source:
        md5 = hashlib.file_digest(source, "md5").hexdigest()
    if baseline is not None:
        required = {"package_name", "certificate_sha256", "version_code", "md5"}
        if not isinstance(baseline, dict) or not required <= baseline.keys():
            raise ValueError("PICO store: incomplete uploaded-version baseline")
        if (
            baseline["package_name"] != PACKAGE
            or baseline["certificate_sha256"] != certificate
        ):
            raise ValueError(
                "PICO store: package/signature differs from the uploaded version"
            )
        if (
            type(baseline["version_code"]) is not int
            or actual_code < baseline["version_code"]
        ):
            raise ValueError("PICO store: versionCode is below the uploaded version")
        if not re.fullmatch(r"[0-9a-f]{32}", baseline["md5"]):
            raise ValueError("PICO store: invalid uploaded-version MD5")
        if md5 == baseline["md5"]:
            raise ValueError(
                "PICO store: duplicate APK matches the uploaded version's MD5"
            )
    return {
        "policy": "pico-store-apk-v1",
        "document": DOCUMENT,
        "checked": "local APK requirements",
        "vendor": "Pico",
        "channel": "appstore",
        "build_type": "Release",
        "device_scope": ["PICO Neo3", "PICO 4", "PICO 4 Ultra"],
        "package_name": PACKAGE,
        "version_name": actual_version,
        "version_code": actual_code,
        "bytes": size,
        "md5": md5,
        "certificate_sha256": certificate,
        "min_sdk": minimum,
        "target_sdk": target,
        "compile_sdk": compile_sdk,
        "architectures": sorted(libraries),
        "launcher": launchers[0],
        "pvr.sdk.version": metadata.get("pvr.sdk.version"),
        "pxr.sdk.version_code": metadata.get("pxr.sdk.version_code"),
        "pvr.app.id": app_id,
        "uploaded_baseline_checked": baseline is not None,
        "platform_review": "not performed; portal metadata and device/content review remain separate",
    }
