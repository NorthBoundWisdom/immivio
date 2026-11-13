"""Verify the architecture audit counts code accesses without lexical false positives."""

from pathlib import Path
import tempfile
import unittest

from tools.audit_godot_test_access import inventory


class GodotTestAccessAudit(unittest.TestCase):
    def test_strings_comments_and_local_declarations_do_not_become_member_accesses(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "app/godot/tests"
            tests.mkdir(parents=True)
            (tests / "test_fixture.gd").write_text(
                "\n".join(
                    [
                        "# menu._comment",
                        'var quoted = "menu._quoted and \\"escaped\\""',
                        "var single = 'menu._single'",
                        'var multiline = """menu._multiline\n# text._inside_string"""',
                        "var _local = 1",
                        "func _helper():",
                        "\tmenu.public()",
                        "\tmenu._real()",
                        "\tmenu\n\t\t. _chained()",
                        "\tmenu._real() # menu._after_comment",
                    ]
                )
            )
            result = inventory(root)
            self.assertEqual(
                [(row["member"], row["accesses"]) for row in result["members"]],
                [("_real", 2), ("_chained", 1)],
            )
            self.assertEqual(result["total_accesses"], 3)

    def test_aggregation_includes_render_fixtures_and_is_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "app/godot/tests"
            tests.mkdir(parents=True)
            (tests / "test_z.gd").write_text("one._alpha()\none._beta()\n")
            (tests / "render_a.gd").write_text("two._beta()\ntwo._alpha()\n")
            (tests / "support.gd").write_text("var public_value = 1\n")
            result = inventory(root)
            self.assertEqual(result["scripts_scanned"], 3)
            self.assertEqual(result["scripts_with_private_access"], 2)
            self.assertEqual(
                [row["member"] for row in result["members"]], ["_alpha", "_beta"]
            )
            self.assertEqual(
                result["members"][0]["tests"],
                [
                    {"file": "app/godot/tests/render_a.gd", "accesses": 1},
                    {"file": "app/godot/tests/test_z.gd", "accesses": 1},
                ],
            )


if __name__ == "__main__":
    unittest.main()
