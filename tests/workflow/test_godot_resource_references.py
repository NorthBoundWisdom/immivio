"""Exercise UID ownership and resource reachability, including unreachable cycles."""

from pathlib import Path
import tempfile
import unittest

from tools import check_godot_resources as checker


class GodotResources(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.files = []
        self.write("app/godot/project.godot", 'run/main_scene="res://scenes/main.tscn"')
        self.write("app/godot/scenes/main.tscn", 'path="res://scripts/main.gd"')
        self.write(
            "app/godot/scripts/main.gd", 'preload("res://shaders/video.gdshader")'
        )
        self.write("app/godot/shaders/video.gdshader", "shader_type spatial;")

    def write(self, path, value):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(value, encoding="utf-8")
        self.files.append(path)

    def check(self):
        return checker.check(self.root, self.files)

    def test_repository_references(self):
        self.assertEqual(checker.check(), [])

    def test_scene_shader_and_test_roots(self):
        self.write("app/godot/scripts/helper.gd", "extends RefCounted")
        self.write("app/godot/tests/check.gd", 'preload("res://scripts/helper.gd")')
        self.assertEqual(self.check(), [])

    def test_orphan_uid_and_unreachable_cycle(self):
        self.write("app/godot/scripts/missing.gd.uid", "uid://abc")
        self.write("app/godot/scripts/a.gd", 'preload("res://scripts/b.gd")')
        self.write("app/godot/scripts/b.gd", 'preload("res://scripts/a.gd")')
        main = self.root / "app/godot/scripts/main.gd"
        main.write_text(main.read_text() + '\n# preload("res://scripts/a.gd")')
        errors = self.check()
        self.assertEqual(sum("Orphan UID" in e for e in errors), 1)
        self.assertEqual(sum("Unreferenced" in e for e in errors), 2)

    def test_uid_and_global_class_references(self):
        self.write("app/godot/scripts/main.gd.uid", "uid://main")
        (self.root / "app/godot/scenes/main.tscn").write_text('uid="uid://main"')
        self.write(
            "app/godot/scripts/data.gd", "class_name SharedData extends RefCounted"
        )
        (self.root / "app/godot/scripts/main.gd").write_text(
            'var data: SharedData\npreload("res://shaders/video.gdshader")'
        )
        self.assertEqual(self.check(), [])
