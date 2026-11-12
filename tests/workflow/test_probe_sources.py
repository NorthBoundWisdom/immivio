"""Performance probes must select real input explicitly before touching ADB."""

from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path
import re
import unittest

from benchmarks import mpv_seek_strategy_device as seek
from benchmarks import mpv_startup_device as startup
from tools.device_probe import PLAYER_FIXTURES

ROOT = Path(__file__).resolve().parents[2]


class ProbeSources(unittest.TestCase):
    common = ["--adb", "adb", "--serial", "serial", "--apk", "debug.apk"]

    def rejected(self, parser, args):
        with redirect_stderr(StringIO()):
            with self.assertRaises(SystemExit) as error:
                parser(args)
        self.assertEqual(error.exception.code, 2)

    def test_seek_requires_a_source(self):
        self.rejected(seek.arguments, self.common + ["--packets", "packets.json"])

    def test_startup_requires_a_source(self):
        self.rejected(startup.arguments, self.common)

    def test_seek_sources_are_explicit_and_mutually_exclusive(self):
        base = self.common + ["--packets", "packets.json"]
        local = seek.arguments(base + ["--fixture", "mpv_performance"])
        self.assertEqual(local.fixture, "mpv_performance")
        self.assertIsNone(local.uri_file)
        network = seek.arguments(base + ["--uri-file", "source.json"])
        self.assertIsNone(network.fixture)
        self.assertEqual(network.uri_file, Path("source.json"))
        self.rejected(
            seek.arguments,
            base + ["--fixture", "mpv_performance", "--uri-file", "source.json"],
        )

    def test_startup_accepts_each_source_but_not_combinations(self):
        for flag, value in [
            ("--fixture", "mpv_performance"),
            ("--original", "owned.mp4"),
            ("--uri-file", "source.json"),
        ]:
            args = startup.arguments(self.common + [flag, value])
            self.assertEqual(
                sum(
                    value is not None
                    for value in [args.fixture, args.original, args.uri_file]
                ),
                1,
            )
        self.rejected(
            startup.arguments,
            self.common + ["--fixture", "mpv_performance", "--original", "owned.mp4"],
        )
        self.rejected(
            startup.arguments,
            self.common + ["--original", "owned.mp4", "--uri-file", "source.json"],
        )

    def test_unknown_fixture_fails_in_argument_parsing(self):
        self.rejected(
            seek.arguments,
            self.common + ["--packets", "packets.json", "--fixture", "missing"],
        )
        self.rejected(startup.arguments, self.common + ["--fixture", "missing"])

    def test_cli_fixture_choices_match_the_receiver(self):
        source = (
            ROOT
            / "android/player-plugin/src/debug/java/org/vrpassthroughplayer/plugin/DebugDiagnosticsReceiver.kt"
        ).read_text()
        match = re.search(r"fixture in\s+setOf\((.*?)\)", source, re.S)
        self.assertIsNotNone(match)
        self.assertEqual(
            set(re.findall(r'"([^"]+)"', match.group(1))), set(PLAYER_FIXTURES)
        )
