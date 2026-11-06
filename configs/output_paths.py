"""One layout for disposable build state and human-facing generated outputs."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil

PLATFORMS = {"Pico": "PICO", "Quest": "QUEST", "OpenXR": "OpenXR"}
ARTIFACT_GROUPS = {"packages", "reports", "tests", "captures", "logs", "archive"}
BUILD_GROUPS = {"android", "native", "staging", "intermediates", "tests"}
GUIDE = "00-目录说明.txt"
MARKER = ".output-layout-v1"


def profile(root, vendor, channel, build_type):
    if (
        vendor not in PLATFORMS
        or channel not in {"appstore", "web"}
        or build_type not in {"Debug", "Release"}
    ):
        raise ValueError("Invalid output profile")
    return Path(root), PLATFORMS[vendor], channel, build_type.lower()


def packages(root, vendor, channel, build_type):
    root, platform, channel, variant = profile(root, vendor, channel, build_type)
    return root / "artifacts/packages" / platform / channel / variant


def build_logs(root, vendor=None, channel="appstore", build_type="Release"):
    if vendor is None:
        return Path(root) / "artifacts/logs/build/common"
    root, platform, channel, variant = profile(root, vendor, channel, build_type)
    return root / "artifacts/logs/build" / platform / channel / variant


def ci_reports(root, channel, build_type):
    profile(root, "Pico", channel, build_type)
    return Path(root) / "artifacts/reports/ci" / channel / build_type.lower()


def apk_for_receipt(receipt_file, record):
    name = record.get("apk", "")
    if not isinstance(name, str) or not re.fullmatch(
        r"Immivio-[A-Za-z0-9._-]+\.apk", name
    ):
        raise ValueError("Invalid APK name in build receipt")
    return Path(receipt_file).parent / name


def guides(root):
    root = Path(root)
    texts = {
        "artifacts": """Immivio 输出目录（仅生成文件，不存放签名密钥）

packages/<平台>/<渠道>/<debug或release>/  最终 APK、构建记录、商店检查报告，找安装包看这里
packages/releases/<tag>/                CI 准备好的三平台发布组合
reports/                               CI 汇总、发布核对、目录迁移记录
tests/                                 自动测试报告与日志
captures/                              界面、真机、图标预览等人工检查资料
logs/                                  构建日志和手工运行日志
archive/                               历史实验、旧依赖和旧输出；不再使用后可自行删除

说明：packages 不会被默认清理。旧目录移动记录在 reports/organization/ 下，没有删除原始数据。
查看目录：python3 configs/android_workflow.py outputs
整理新增散落文件：python3 configs/android_workflow.py organize
预览日志清理：python3 configs/android_workflow.py clean --scope logs --dry-run
清理日志：python3 configs/android_workflow.py clean --scope logs
同样可使用 --scope tests、captures、archive；tests 同时清理测试报告和 build/tests 临时输入。
签名在项目外 ~/.config/immivio/signing/（Windows 为 %APPDATA%/Immivio/signing/），请独立备份。
""",
        "build": """Immivio 构建中间文件（可重新生成，不存放最终 APK 或签名密钥）

android/        Android 配置状态、生成参数与 Godot API
native/         原生主机辅助程序构建
staging/        已验证依赖的展开、CI 下载暂存
intermediates/  临时脚本、APK 原生库检查（新检查完成后自动移除展开文件）
tests/          测试输入、临时配置、测试用户数据

历史旧 build 目录内容已归档到 artifacts/archive/legacy-build/，保留原名供查找。
旧 APK 解包检查位于 intermediates/legacy-apk-inspection/，是可重新生成的文件。
仅清理中间文件：python3 configs/android_workflow.py clean --scope intermediates
预览全部构建清理：python3 configs/android_workflow.py clean --scope build --dry-run
清理：python3 configs/android_workflow.py clean --scope build
清理后重新 configure；最终安装包、历史归档、依赖缓存和项目外签名均不会被此命令删除。
""",
    }
    for folder, text in texts.items():
        directory = root / folder
        directory.mkdir(parents=True, exist_ok=True)
        (directory / GUIDE).write_text(text, encoding="utf-8")


def describe(root):
    root = Path(root)
    return {
        "packages": str(root / "artifacts/packages"),
        "reports": str(root / "artifacts/reports"),
        "tests": str(root / "artifacts/tests"),
        "captures": str(root / "artifacts/captures"),
        "logs": str(root / "artifacts/logs"),
        "archive": str(root / "artifacts/archive"),
        "intermediates": str(root / "build"),
    }


def _inside(root, path):
    path = Path(path)
    if not path.resolve().is_relative_to(Path(root).resolve()) or path.is_symlink():
        raise RuntimeError(f"Refusing symlinked or escaping output path: {path}")


def _private_files(path):
    if path.is_file():
        files = [path]
    else:
        files = (
            Path(base) / name
            for base, _, names in os.walk(path, followlinks=False)
            for name in names
        )
    return [
        p
        for p in files
        if p.suffix.lower() in {".keystore", ".jks", ".p12", ".pfx"}
        or p.name.endswith("-signing.json")
    ]


def clean(root, scope="build", dry_run=False):
    from configs.workspace_lock import workspace_mutation_lock

    root = Path(root)
    targets = {
        "build": [root / "build"],
        "intermediates": [root / "build/intermediates"],
        "logs": [root / "artifacts/logs"],
        "tests": [root / "artifacts/tests", root / "build/tests"],
        "captures": [root / "artifacts/captures"],
        "archive": [root / "artifacts/archive"],
    }
    if scope not in targets:
        raise ValueError(
            "Cleanup scope must be build, intermediates, logs, tests, captures or archive"
        )
    with workspace_mutation_lock(root):
        existing = []
        # Validate the entire scope before deleting any of its directories.
        for target in targets[scope]:
            _inside(root, target)
            if target.exists():
                if _private_files(target):
                    raise RuntimeError(
                        f"Signing material found in {target}; move it to persistent private storage before cleanup"
                    )
                existing.append(target)
        for target in existing:
            print(("Would remove " if dry_run else "Removing ") + str(target))
            if not dry_run:
                shutil.rmtree(target)


def _receipt_destinations(root):
    result = {}
    for receipt in (root / "artifacts").glob("*.build.json"):
        try:
            record = json.loads(receipt.read_text())
            apk = apk_for_receipt(receipt, record)
            destination = packages(
                root,
                record["vendor"],
                record.get("channel", "appstore"),
                record["build_type"],
            )
        except (ValueError, KeyError, OSError):
            continue
        if not apk.is_file():
            continue
        if any(
            (destination / item.name).exists()
            for item in (apk, receipt, apk.with_suffix(".store-report.json"))
        ):
            destination = root / "artifacts/archive/legacy-packages" / apk.stem
            original = destination
            number = 1
            while destination.exists():
                destination = original.with_name(original.name + f".previous-{number}")
                number += 1
        for source in (apk, receipt, apk.with_suffix(".store-report.json")):
            if source.exists():
                result[source] = destination / source.name
    return result


def organization_plan(root):
    root = Path(root)
    moves = _receipt_destinations(root)
    artifacts = root / "artifacts"
    if artifacts.exists():
        for source in artifacts.iterdir():
            name = source.name
            if source in moves or name in ARTIFACT_GROUPS | {GUIDE, MARKER}:
                continue
            if name == "signing":
                if any(source.iterdir()):
                    raise RuntimeError(
                        "Legacy artifacts/signing is not empty; migrate signing material first"
                    )
                continue
            if name == "native-inspection":
                target = root / "build/intermediates/legacy-apk-inspection"
            elif name == "source-tests":
                target = artifacts / "tests/godot/previous-layout"
            elif name == "source-test-userdata":
                target = root / "build/tests/userdata/previous-layout"
            elif source.suffix == ".log":
                target = artifacts / "logs/manual" / name
            elif source.is_dir() and "device" in name:
                target = artifacts / "captures/device" / name
            elif "verification" in name:
                target = artifacts / "reports/releases" / name
            elif (
                source.suffix.lower() in {".png", ".jpg", ".webp"}
                or source.is_dir()
                and any(
                    word in name
                    for word in ("frames", "padding", "subtitle", "popup", "brand")
                )
            ):
                category = (
                    "branding"
                    if any(word in name for word in ("brand", "immivio"))
                    else "ui"
                )
                target = artifacts / "captures" / category / name
            else:
                target = artifacts / "archive/legacy-artifacts" / name
            moves[source] = target
        # Move earlier flat logs into an explicitly labelled historical subfolder.
        logs = artifacts / "logs"
        if logs.exists():
            for source in logs.iterdir():
                if source.name not in {"build", "manual", "tools"}:
                    moves[source] = logs / "build/previous-layout" / source.name
    build = root / "build"
    if build.exists():
        for source in build.iterdir():
            if source.name not in BUILD_GROUPS | {GUIDE, MARKER}:
                moves[source] = artifacts / "archive/legacy-build" / source.name
    planned = []
    used = set()
    for source, target in sorted(moves.items(), key=lambda item: str(item[0])):
        _inside(root, source)
        _inside(root, target)
        if _private_files(source):
            raise RuntimeError(
                f"Signing material found in {source}; refusing to archive private keys"
            )
        original = target
        suffix = 1
        while target.exists() or target in used:
            target = original.with_name(original.name + f".previous-{suffix}")
            suffix += 1
        used.add(target)
        planned.append((source, target))
    return planned


def organize(root, dry_run=False):
    """Reversible same-workspace moves; no file data is deleted or overwritten."""
    from configs.workspace_lock import workspace_mutation_lock

    root = Path(root)
    with workspace_mutation_lock(root):
        planned = organization_plan(root)
        for source, target in planned:
            print(f"{source.relative_to(root)} -> {target.relative_to(root)}")
        if dry_run:
            if not planned:
                print("Already organized; no moves needed")
            return planned
        if not planned:
            guides(root)
            print("Already organized; no moves needed")
            return planned
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
        report = root / "artifacts/reports/organization" / (timestamp + ".json")
        report.parent.mkdir(parents=True, exist_ok=True)
        journal = {
            "operation": "move only; no deletion",
            "planned": [
                {
                    "from": str(source.relative_to(root)),
                    "to": str(target.relative_to(root)),
                }
                for source, target in planned
            ],
            "moves": [],
        }
        report.write_text(
            json.dumps(journal, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        for source, target in planned:
            target.parent.mkdir(parents=True, exist_ok=True)
            _inside(root, target)
            if target.exists():
                raise RuntimeError(
                    f"Destination appeared during organization; refusing to overwrite {target}"
                )
            source.rename(target)
            journal["moves"].append(
                {
                    "from": str(source.relative_to(root)),
                    "to": str(target.relative_to(root)),
                }
            )
            report.write_text(
                json.dumps(journal, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        signing = root / "artifacts/signing"
        if signing.is_dir() and not any(signing.iterdir()):
            signing.rmdir()
        guides(root)
        for folder in ("artifacts", "build"):
            (root / folder / MARKER).write_text("1\n")
        print(f"Organized {len(planned)} entries. Move journal: {report}")
        return planned
