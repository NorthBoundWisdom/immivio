from __future__ import annotations

import ntpath
import os
import posixpath
import sys
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any

from freecm.repo_commands import REPO_COMMAND_MANIFEST_PATH, validate_repo_command_manifest
from freecm.subprocess_utils import run_logged_command

TEST_LEVEL_L0 = "l0"
TEST_LEVEL_L1 = "l1"
TEST_LEVEL_L2 = "l2"
TEST_LEVEL_L3 = "l3"
TEST_LEVEL_L4 = "l4"
TEST_LEVEL_PRECOMMIT = "precommit"
TEST_LEVEL_ALL = "all"
TEST_LEVEL_CHOICES = (
    TEST_LEVEL_L0,
    TEST_LEVEL_L1,
    TEST_LEVEL_L2,
    TEST_LEVEL_L3,
    TEST_LEVEL_L4,
    TEST_LEVEL_PRECOMMIT,
    TEST_LEVEL_ALL,
)
if TYPE_CHECKING:
    PathValue = str | Path
else:
    PathValue = Any


@dataclass(frozen=True)
class AndroidWorkflowConfig:
    repo_root: Path
    shell_check_scripts: Sequence[PathValue] = ()
    python_check_files: Sequence[PathValue] = ()
    l0_gradle_tasks: Sequence[str] = ()
    l1_gradle_tasks: Sequence[str] = ()
    l2_scripts: Sequence[PathValue] = ()
    l3_scripts: Sequence[PathValue] = ()
    l4_scripts: Sequence[PathValue] = ()
    gradle_wrapper: PathValue | None = None
    host_platform: str = sys.platform

    def __post_init__(self) -> None:
        object.__setattr__(self, "repo_root", Path(self.repo_root).resolve())
        for field_name in (
            "shell_check_scripts",
            "python_check_files",
            "l0_gradle_tasks",
            "l1_gradle_tasks",
            "l2_scripts",
            "l3_scripts",
            "l4_scripts",
        ):
            object.__setattr__(self, field_name, tuple(getattr(self, field_name)))


def android_environment(
    base_env: Mapping[str, str] | None = None,
    *,
    home: Path | None = None,
    homebrew_jdk_path: Path = Path("/opt/homebrew/opt/openjdk@17"),
    platform: str = sys.platform,
) -> dict[str, str]:
    env = dict(os.environ if base_env is None else base_env)
    home_root = Path.home() if home is None else Path(home)
    sdk_root = env.get("ANDROID_SDK_ROOT") or env.get("ANDROID_HOME")
    if not sdk_root:
        sdk_root = _default_android_sdk_root(env, home_root, platform)
    env["ANDROID_HOME"] = sdk_root
    env["ANDROID_SDK_ROOT"] = sdk_root

    java_home = env.get("JAVA_HOME")
    if not java_home and platform == "darwin" and homebrew_jdk_path.is_dir():
        java_home = str(homebrew_jdk_path)
        env["JAVA_HOME"] = java_home

    path_entries: list[str] = []
    if java_home:
        path_entries.append(_join_env_path(java_home, "bin", platform))
    path_entries.extend(
        [
            _join_env_path(sdk_root, "platform-tools", platform),
            _join_env_path(sdk_root, "emulator", platform),
            _join_env_path(sdk_root, "cmdline-tools/latest/bin", platform),
        ]
    )
    path_key = _environment_path_key(env, platform)
    existing_path = env.get(path_key, "")
    if existing_path:
        path_entries.append(existing_path)
    env[path_key] = _path_separator(platform).join(path_entries)
    return env


def gradlew_command(
    repo_root: Path,
    args: Iterable[str],
    *,
    gradle_wrapper: PathValue | None = None,
    platform: str = sys.platform,
) -> list[str]:
    if gradle_wrapper is None:
        gradle_wrapper = "gradlew.bat" if _is_windows(platform) else "gradlew"
    path_module = ntpath if _is_windows(platform) else posixpath
    wrapper_path = path_module.normpath(str(gradle_wrapper))
    if not path_module.isabs(wrapper_path):
        wrapper_path = path_module.normpath(path_module.join(str(repo_root), wrapper_path))
    return [wrapper_path, *args]


def run_test_level(
    config: AndroidWorkflowConfig,
    level: str,
    *,
    env: Mapping[str, str] | None = None,
) -> None:
    workflow_env = android_environment(env, platform=config.host_platform)
    if level == TEST_LEVEL_L0:
        _run_l0(config, workflow_env)
    elif level == TEST_LEVEL_L1:
        _run_l1(config, workflow_env)
    elif level == TEST_LEVEL_L2:
        _run_scripts(config, TEST_LEVEL_L2, config.l2_scripts, workflow_env)
    elif level == TEST_LEVEL_L3:
        _run_scripts(config, TEST_LEVEL_L3, config.l3_scripts, workflow_env)
    elif level == TEST_LEVEL_L4:
        _run_scripts(config, TEST_LEVEL_L4, config.l4_scripts, workflow_env)
    elif level == TEST_LEVEL_PRECOMMIT:
        _run_l0(config, workflow_env)
        _run_l1(config, workflow_env)
        _run_scripts(config, TEST_LEVEL_L2, config.l2_scripts, workflow_env)
    elif level == TEST_LEVEL_ALL:
        _run_l0(config, workflow_env)
        _run_l1(config, workflow_env)
        _run_scripts(config, TEST_LEVEL_L2, config.l2_scripts, workflow_env)
        _run_scripts(config, TEST_LEVEL_L3, config.l3_scripts, workflow_env)
        _run_scripts(config, TEST_LEVEL_L4, config.l4_scripts, workflow_env)
    else:
        raise ValueError(f"Unsupported test level: {level}")


def _run_l0(
    config: AndroidWorkflowConfig,
    env: Mapping[str, str],
) -> None:
    for script in config.shell_check_scripts:
        run_logged_command(
            ["bash", "-n", _repo_path(config.repo_root, script)],
            cwd=config.repo_root,
            env=dict(env),
            prefix=f"\n[{TEST_LEVEL_L0}] ",
        )
    if config.python_check_files:
        run_logged_command(
            [
                "python3",
                "-m",
                "py_compile",
                *(_repo_path(config.repo_root, path) for path in config.python_check_files),
            ],
            cwd=config.repo_root,
            env=dict(env),
            prefix=f"\n[{TEST_LEVEL_L0}] ",
        )
    run_logged_command(
        ["git", "-C", str(config.repo_root), "diff", "--check"],
        cwd=config.repo_root,
        env=dict(env),
        prefix=f"\n[{TEST_LEVEL_L0}] ",
    )
    if config.l0_gradle_tasks:
        run_logged_command(
            gradlew_command(
                config.repo_root,
                config.l0_gradle_tasks,
                gradle_wrapper=config.gradle_wrapper,
                platform=config.host_platform,
            ),
            cwd=config.repo_root,
            env=dict(env),
            prefix=f"\n[{TEST_LEVEL_L0}] ",
        )


def _run_l1(
    config: AndroidWorkflowConfig,
    env: Mapping[str, str],
) -> None:
    if config.l1_gradle_tasks:
        run_logged_command(
            gradlew_command(
                config.repo_root,
                config.l1_gradle_tasks,
                gradle_wrapper=config.gradle_wrapper,
                platform=config.host_platform,
            ),
            cwd=config.repo_root,
            env=dict(env),
            prefix=f"\n[{TEST_LEVEL_L1}] ",
        )

    if (config.repo_root / REPO_COMMAND_MANIFEST_PATH).is_file():
        validate_repo_command_manifest(config.repo_root)


def _run_scripts(
    config: AndroidWorkflowConfig,
    label: str,
    scripts: Sequence[PathValue],
    env: Mapping[str, str],
) -> None:
    for script in scripts:
        run_logged_command(
            [_repo_path(config.repo_root, script)],
            cwd=config.repo_root,
            env=dict(env),
            prefix=f"\n[{label}] ",
        )


def _repo_path(repo_root: Path, path: PathValue) -> str:
    candidate = Path(path)
    if candidate.is_absolute():
        return str(candidate)
    return str(repo_root / candidate)


def _default_android_sdk_root(env: Mapping[str, str], home: Path, platform: str) -> str:
    if _is_windows(platform):
        local_app_data = env.get("LOCALAPPDATA")
        if local_app_data:
            return ntpath.normpath(ntpath.join(local_app_data, "Android", "Sdk"))
        return ntpath.normpath(ntpath.join(str(home), "AppData", "Local", "Android", "Sdk"))
    if platform == "darwin":
        return posixpath.join(str(home), "Library", "Android", "sdk")
    return posixpath.join(str(home), "Android", "Sdk")


def _join_env_path(root: str, relative: str, platform: str) -> str:
    if _is_windows(platform):
        return ntpath.normpath(ntpath.join(root, *relative.split("/")))
    return posixpath.join(root, *relative.split("/"))


def _environment_path_key(env: Mapping[str, str], platform: str) -> str:
    if not _is_windows(platform):
        return "PATH"
    return next((key for key in env if key.lower() == "path"), "Path")


def _path_separator(platform: str) -> str:
    return ";" if _is_windows(platform) else ":"


def _is_windows(platform: str) -> bool:
    return platform.startswith("win")


__all__ = (
    "TEST_LEVEL_ALL",
    "TEST_LEVEL_CHOICES",
    "TEST_LEVEL_L0",
    "TEST_LEVEL_L1",
    "TEST_LEVEL_L2",
    "TEST_LEVEL_L3",
    "TEST_LEVEL_L4",
    "TEST_LEVEL_PRECOMMIT",
    "AndroidWorkflowConfig",
    "android_environment",
    "gradlew_command",
    "run_test_level",
)
