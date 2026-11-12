"""Guard catalog provenance without requiring Godot or Android."""

import json
from pathlib import Path
import tempfile
import unittest

from tools import check_translations as checker


class TranslationConsistency(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalog = {
            language: {"Hello": "translated"} for language in ["zh", "zh_Hant", "ja"]
        }
        self.write("app/godot/scripts/main.gd", 'I18n.t("Hello")\n')
        self.write("app/godot/i18n/licenses.json", "{}")
        self.write("app/godot/i18n/dynamic_keys.json", "[]")
        self.save()

    def write(self, path, value):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(value, encoding="utf-8")

    def save(self):
        self.write("app/godot/i18n/translations.json", json.dumps(self.catalog))

    def test_repository_catalog(self):
        self.assertEqual(checker.check(), [])

    def test_missing_literal_and_locale_drift(self):
        self.write("app/godot/scripts/main.gd", 'I18n.t("Absent")\n')
        self.catalog["ja"].clear()
        self.save()
        errors = checker.check(self.root)
        self.assertTrue(any("Missing literal translation" in e for e in errors))
        self.assertTrue(any("Locale key mismatch" in e for e in errors))

    def test_comments_are_not_provenance(self):
        self.write("app/godot/scripts/main.gd", '# "Hello"\n')
        self.assertTrue(any("no source literal" in e for e in checker.check(self.root)))

    def test_kotlin_errors_and_license_literals_are_provenance(self):
        self.write("app/godot/scripts/main.gd", "")
        self.write(
            "android/player-plugin/src/main/java/Error.kt",
            'error("Hello") // "Ignored"\n',
        )
        self.assertEqual(checker.check(self.root), [])
        self.write("android/player-plugin/src/main/java/Error.kt", "")
        self.write("app/godot/i18n/licenses.json", '{"license": "Hello"}')
        self.assertEqual(checker.check(self.root), [])

    def test_dynamic_keys_need_live_evidence(self):
        self.write("app/godot/scripts/main.gd", "state.capitalize()")
        self.write(
            "app/godot/i18n/dynamic_keys.json",
            json.dumps(
                [
                    {
                        "keys": ["Hello"],
                        "source": "app/godot/scripts/main.gd",
                        "expression": "state.capitalize()",
                        "reason": "Native state",
                    }
                ]
            ),
        )
        self.assertEqual(checker.check(self.root), [])
        self.write("app/godot/scripts/main.gd", "")
        self.assertTrue(any("Stale dynamic" in e for e in checker.check(self.root)))

    def test_duplicate_json_keys_are_rejected(self):
        self.write("app/godot/i18n/translations.json", '{"zh": {}, "zh": {}}')
        self.assertTrue(
            any("Duplicate JSON key" in e for e in checker.check(self.root))
        )

    def test_ternary_branches_and_escaped_literals(self):
        self.write(
            "app/godot/scripts/main.gd", 'I18n.t("Hello" if enabled else "Missing")\n'
        )
        self.assertTrue(any("Missing" in e for e in checker.check(self.root)))
        tokens, _ = checker.literals('# "comment"\nI18n.t("quote: \\"ok\\"")')
        self.assertEqual([v for _, _, v in tokens], ['quote: "ok"'])

    def test_raw_kotlin_and_gdscript_multiline_escapes(self):
        tokens, _ = checker.literals(r'"""price: \$5"""', kotlin=True)
        self.assertEqual(tokens[0][2], r"price: \$5")
        tokens, _ = checker.literals('"""line\\nnext"""')
        self.assertEqual(tokens[0][2], "line\nnext")
