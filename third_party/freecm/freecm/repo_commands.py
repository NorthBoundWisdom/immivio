"""Lightweight validation for downstream repository command manifests."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, NoReturn

from .errors import RepoCommandManifestError
from .jsonc import strip_jsonc_comments, strip_jsonc_trailing_commas

REPO_COMMAND_MANIFEST_PATH = Path("configs/freecm.commands.jsonc")
REPO_COMMAND_ACTIONS = ("config", "build", "run", "test", "package")
REPO_COMMAND_DEPENDENT_ACTIONS = ("build", "run", "test", "package")
SUPPORTED_REPO_COMMAND_PLATFORMS = ("darwin", "linux", "win32")
SUPPORTED_REPO_COMMAND_MANIFEST_VERSION = 2
_MISSING = object()


@dataclass(frozen=True)
class RepoCommandManifestSummary:
    """Small success receipt returned by the headless validator."""

    manifest_path: Path
    configuration_count: int
    variant_count: int


@dataclass(frozen=True)
class _Variant:
    id: str
    platforms: tuple[str, ...] | None = None
    default: bool = False
    defaults: Mapping[str, str] | None = None
    configurations: tuple[str, ...] = ()


def validate_repo_command_manifest(repo_root: str | Path) -> RepoCommandManifestSummary:
    """Validate one downstream manifest with no Node or third-party Python dependency."""

    manifest_path = Path(repo_root).resolve() / REPO_COMMAND_MANIFEST_PATH
    try:
        text = manifest_path.read_text(encoding="utf-8")
    except OSError as error:
        raise RepoCommandManifestError(f"Unable to read {manifest_path}: {error}") from error
    return validate_repo_command_manifest_text(text, manifest_path=manifest_path)


def validate_repo_command_manifest_text(
    text: str,
    *,
    manifest_path: str | Path = REPO_COMMAND_MANIFEST_PATH,
) -> RepoCommandManifestSummary:
    """Validate manifest text and return only a compact structural summary."""

    path = Path(manifest_path)
    value = _parse_jsonc(text, path)
    if not isinstance(value, dict):
        _fail(path, "expected top-level object")
    if value.get("version") != SUPPORTED_REPO_COMMAND_MANIFEST_VERSION:
        _fail(path, f"version must be {SUPPORTED_REPO_COMMAND_MANIFEST_VERSION}")

    commands = value.get("commands")
    if not isinstance(commands, dict):
        _fail(path, "commands must be an object")

    actions = {
        action: _parse_action(
            action,
            commands[action] if action in commands else _MISSING,
            path,
        )
        for action in REPO_COMMAND_ACTIONS
    }
    _validate_relationships(actions, path)
    return RepoCommandManifestSummary(
        manifest_path=path,
        configuration_count=len(actions["config"]),
        variant_count=sum(len(variants) for variants in actions.values()),
    )


def _parse_jsonc(text: str, manifest_path: Path) -> Any:
    normalized = strip_jsonc_trailing_commas(strip_jsonc_comments(text))
    try:
        return json.loads(normalized)
    except json.JSONDecodeError as error:
        raise RepoCommandManifestError(
            f"Invalid JSONC in {manifest_path}: {error.msg} "
            f"at line {error.lineno} column {error.colno}"
        ) from error


def _parse_action(action: str, value: object, manifest_path: Path) -> list[_Variant]:
    if value is _MISSING:
        return []
    if not isinstance(value, list):
        _fail(manifest_path, f"commands.{action} must be an array")

    variants = [
        _parse_variant(action, entry, index, manifest_path) for index, entry in enumerate(value)
    ]
    _assert_unique_strings(
        [variant.id for variant in variants],
        manifest_path,
        f"commands.{action}",
        noun="id",
    )
    return variants


def _parse_variant(
    action: str,
    value: object,
    index: int,
    manifest_path: Path,
) -> _Variant:
    prefix = f"commands.{action}[{index}]"
    if not isinstance(value, dict):
        _fail(manifest_path, f"{prefix} must be an object")

    variant_id = _required_string(value.get("id"), manifest_path, f"{prefix}.id")
    _required_string(value.get("label"), manifest_path, f"{prefix}.label")
    _parse_variant_steps(value, manifest_path, prefix)
    if "description" in value and not isinstance(value["description"], str):
        _fail(manifest_path, f"{prefix}.description must be a string")

    if action == "config":
        return _parse_config_fields(value, variant_id, manifest_path, prefix)
    return _parse_dependent_fields(value, variant_id, manifest_path, prefix)


def _parse_config_fields(
    value: Mapping[str, object],
    variant_id: str,
    manifest_path: Path,
    prefix: str,
) -> _Variant:
    if "configurations" in value:
        _fail(
            manifest_path,
            f"{prefix}.configurations is only valid for downstream actions",
        )

    platforms: tuple[str, ...] | None = None
    if "platforms" in value:
        platforms = _required_non_empty_string_array(
            value["platforms"], manifest_path, f"{prefix}.platforms"
        )
        _assert_unique_strings(platforms, manifest_path, f"{prefix}.platforms")
        for platform in platforms:
            if platform not in SUPPORTED_REPO_COMMAND_PLATFORMS:
                _fail(
                    manifest_path,
                    f"{prefix}.platforms contains unsupported platform {platform!r}",
                )

    default = value.get("default", False)
    if "default" in value and not isinstance(default, bool):
        _fail(manifest_path, f"{prefix}.default must be boolean")

    defaults_value = value.get("defaults")
    if not isinstance(defaults_value, dict):
        _fail(manifest_path, f"{prefix}.defaults must be an object")
    defaults: dict[str, str] = {}
    for action, referenced_id in defaults_value.items():
        if action not in REPO_COMMAND_DEPENDENT_ACTIONS:
            _fail(
                manifest_path,
                f"{prefix}.defaults contains unsupported action {action!r}",
            )
        defaults[action] = _required_string(
            referenced_id, manifest_path, f"{prefix}.defaults.{action}"
        )

    if "readiness" in value:
        _parse_readiness(value["readiness"], manifest_path, f"{prefix}.readiness")

    return _Variant(
        id=variant_id,
        platforms=platforms,
        default=bool(default),
        defaults=defaults,
    )


def _parse_dependent_fields(
    value: Mapping[str, object],
    variant_id: str,
    manifest_path: Path,
    prefix: str,
) -> _Variant:
    for config_only_field in ("platforms", "default", "defaults", "readiness"):
        if config_only_field in value:
            _fail(
                manifest_path,
                f"{prefix}.{config_only_field} is only valid for Config variants",
            )

    configurations = _required_non_empty_string_array(
        value.get("configurations"), manifest_path, f"{prefix}.configurations"
    )
    _assert_unique_strings(configurations, manifest_path, f"{prefix}.configurations")
    return _Variant(id=variant_id, configurations=configurations)


def _parse_readiness(value: object, manifest_path: Path, field_path: str) -> None:
    if not isinstance(value, dict):
        _fail(manifest_path, f"{field_path} must be an object")
    for kind in ("inputs", "outputs"):
        raw_paths = value[kind] if kind in value else _MISSING
        paths = _optional_string_array(raw_paths, manifest_path, f"{field_path}.{kind}")
        _assert_unique_strings(paths, manifest_path, f"{field_path}.{kind}")
        for repo_path in paths:
            _assert_repo_relative_path(repo_path, manifest_path, f"{field_path}.{kind}")


def _parse_variant_steps(
    value: Mapping[str, object],
    manifest_path: Path,
    prefix: str,
) -> None:
    if "steps" in value:
        if "command" in value or "args" in value:
            _fail(
                manifest_path,
                f"{prefix} must use either command/args or steps, not both",
            )
        steps = value["steps"]
        if not isinstance(steps, list) or not steps:
            _fail(manifest_path, f"{prefix}.steps must be a non-empty array")
        for index, step in enumerate(steps):
            _parse_command_step(step, manifest_path, f"{prefix}.steps[{index}]")
        return

    _required_string(value.get("command"), manifest_path, f"{prefix}.command")
    _required_string_array(value.get("args"), manifest_path, f"{prefix}.args")


def _parse_command_step(value: object, manifest_path: Path, prefix: str) -> None:
    if not isinstance(value, dict):
        _fail(manifest_path, f"{prefix} must be an object")
    _required_string(value.get("command"), manifest_path, f"{prefix}.command")
    _required_string_array(value.get("args"), manifest_path, f"{prefix}.args")


def _validate_relationships(
    actions: Mapping[str, Sequence[_Variant]],
    manifest_path: Path,
) -> None:
    configurations = actions["config"]
    configuration_ids = {configuration.id for configuration in configurations}

    for action in REPO_COMMAND_DEPENDENT_ACTIONS:
        for variant in actions[action]:
            for configuration_id in variant.configurations:
                if configuration_id not in configuration_ids:
                    _fail(
                        manifest_path,
                        f"commands.{action} variant {variant.id!r} references unknown "
                        f"Config {configuration_id!r}",
                    )

    for configuration in configurations:
        defaults = configuration.defaults or {}
        for action in REPO_COMMAND_DEPENDENT_ACTIONS:
            variants = [
                variant for variant in actions[action] if configuration.id in variant.configurations
            ]
            default_id = defaults.get(action)
            if not variants:
                if default_id is not None:
                    _fail(
                        manifest_path,
                        f"Config {configuration.id!r} defaults.{action} references "
                        f"{default_id!r}, but no {action} variants support that Config",
                    )
                continue
            if default_id is None:
                _fail(
                    manifest_path,
                    f"Config {configuration.id!r} must declare defaults.{action} because "
                    f"compatible {action} variants exist",
                )
            if not any(variant.id == default_id for variant in variants):
                _fail(
                    manifest_path,
                    f"Config {configuration.id!r} defaults.{action} {default_id!r} is not a "
                    f"compatible {action} variant",
                )

    for platform in SUPPORTED_REPO_COMMAND_PLATFORMS:
        compatible = [
            configuration
            for configuration in configurations
            if configuration.platforms is None or platform in configuration.platforms
        ]
        if not compatible:
            continue
        default_count = sum(configuration.default for configuration in compatible)
        if default_count != 1:
            _fail(
                manifest_path,
                f"platform {platform} must have exactly one default Config; found {default_count}",
            )


def _required_string(value: object, manifest_path: Path, field_path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        _fail(manifest_path, f"{field_path} must be a non-empty string")
    return value


def _required_string_array(
    value: object,
    manifest_path: Path,
    field_path: str,
) -> tuple[str, ...]:
    if not isinstance(value, list) or not all(isinstance(entry, str) for entry in value):
        _fail(manifest_path, f"{field_path} must be a string array")
    return tuple(value)


def _required_non_empty_string_array(
    value: object,
    manifest_path: Path,
    field_path: str,
) -> tuple[str, ...]:
    result = _required_string_array(value, manifest_path, field_path)
    if not result or any(not entry.strip() for entry in result):
        _fail(manifest_path, f"{field_path} must be a non-empty string array")
    return result


def _optional_string_array(
    value: object,
    manifest_path: Path,
    field_path: str,
) -> tuple[str, ...]:
    if value is _MISSING:
        return ()
    result = _required_string_array(value, manifest_path, field_path)
    if any(not entry.strip() for entry in result):
        _fail(manifest_path, f"{field_path} entries must be non-empty strings")
    return result


def _assert_unique_strings(
    values: Sequence[str],
    manifest_path: Path,
    field_path: str,
    *,
    noun: str = "value",
) -> None:
    seen: set[str] = set()
    for value in values:
        if value in seen:
            _fail(manifest_path, f"{field_path} contains duplicate {noun} {value!r}")
        seen.add(value)


def _assert_repo_relative_path(value: str, manifest_path: Path, field_path: str) -> None:
    normalized = value.replace("\\", "/")
    posix_path = PurePosixPath(normalized)
    if posix_path.is_absolute() or PureWindowsPath(value).is_absolute() or ".." in posix_path.parts:
        _fail(
            manifest_path,
            f"{field_path} path {value!r} must stay within the repository",
        )


def _fail(manifest_path: Path, message: str) -> NoReturn:
    raise RepoCommandManifestError(f"Invalid command manifest {manifest_path}: {message}")
