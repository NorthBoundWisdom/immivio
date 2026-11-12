"""Check catalog provenance and literal UI translations without running Godot."""

from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
STRING = r'"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27'


def literals(text: str, kotlin: bool = False) -> tuple[list[tuple[int, int, str]], str]:
    comments = r"//[^\n]*|/\*[\s\S]*?\*/" if kotlin else r"\#[^\n]*"
    pattern = re.compile(r"(?P<comment>" + comments + r")|(?P<string>" + STRING + r")")
    result = []
    clean = list(text)
    for match in pattern.finditer(text):
        if match.group("comment") is not None:
            clean[match.start() : match.end()] = [
                "\n" if c == "\n" else " " for c in match.group()
            ]
            continue
        token = match.group()
        if kotlin:
            token = token.replace("\\$", "$")
        try:
            value = (
                token[3:-3]
                if token.startswith(('"""', "'''"))
                else ast.literal_eval(token)
            )
        except (SyntaxError, ValueError):
            continue
        if isinstance(value, str):
            result.append((match.start(), match.end(), value))
    return result, "".join(clean)


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def check(root: Path = ROOT) -> list[str]:
    errors = []
    try:
        catalog = json.loads(
            (root / "app/godot/i18n/translations.json").read_text(encoding="utf-8"),
            object_pairs_hook=unique_object,
        )
        dynamic = json.loads(
            (root / "app/godot/i18n/dynamic_keys.json").read_text(encoding="utf-8"),
            object_pairs_hook=unique_object,
        )
    except (ValueError, OSError) as error:
        return [str(error)]
    if set(catalog) != {"zh", "zh_Hant", "ja"}:
        errors.append("Catalog must contain zh, zh_Hant and ja")
    keys = set(catalog.get("zh", {}))
    for language, entries in catalog.items():
        if not isinstance(entries, dict):
            errors.append(f"Invalid catalog: {language}")
            continue
        if set(entries) != keys:
            errors.append(f"Locale key mismatch: {language}")
        for key, value in entries.items():
            if not isinstance(value, str) or not value:
                errors.append(f"Empty/invalid translation: {language}: {key}")
    sources = [
        *sorted((root / "app/godot/scripts").rglob("*.gd")),
        *sorted((root / "android/player-plugin/src/main").rglob("*.kt")),
        root / "app/godot/i18n/licenses.json",
    ]
    values = set()
    for path in sources:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        tokens, clean = literals(text, path.suffix == ".kt")
        values.update(value for _, _, value in tokens)
        if path.suffix != ".gd":
            continue
        starts = {start: (end, value) for start, end, value in tokens}
        # Check direct literals and the literal branches of GDScript ternaries.
        for call in re.finditer(r"\bI18n\s*\.\s*t\s*\(\s*", clean):
            first = starts.get(call.end())
            if not first:
                continue
            end, value = first
            tail = clean[end:].lstrip()
            candidates = (
                [value] if tail.startswith(")") or re.match(r"if\b", tail) else []
            )
            if re.match(r"if\b", tail):
                depth = 1
                cursor = end
                token_map = {start: (stop, val) for start, stop, val in tokens}
                while cursor < len(clean) and depth:
                    if cursor in token_map:
                        stop, val = token_map[cursor]
                        if re.search(r"\belse\s*$", clean[end:cursor]):
                            candidates.append(val)
                        cursor = stop
                        continue
                    depth += (clean[cursor] == "(") - (clean[cursor] == ")")
                    cursor += 1
            for value in candidates:
                if value and value not in keys:
                    line = text.count("\n", 0, call.start()) + 1
                    errors.append(
                        f"Missing literal translation: {path.relative_to(root)}:{line}: {value}"
                    )
    allowed = set()
    for entry in dynamic:
        source = root / entry["source"]
        if (
            not entry.get("reason")
            or not source.is_file()
            or entry["expression"] not in source.read_text(encoding="utf-8")
        ):
            errors.append(f"Stale dynamic-key evidence: {entry.get('source')}")
        for key in entry["keys"]:
            if key in allowed or key not in keys:
                errors.append(f"Invalid/duplicate dynamic key: {key}")
            allowed.add(key)
    errors.extend(
        f"Catalog key has no source literal or dynamic evidence: {key}"
        for key in sorted(keys - values - allowed)
    )
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    errors = check(args.root)
    for error in errors:
        print(error)
    print(f"Translation consistency: {len(errors)} errors")
    raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
