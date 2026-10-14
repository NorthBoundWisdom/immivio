"""Exercise actual downloads and archive boundaries with local-only fixtures."""

from contextlib import contextmanager
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
import zipfile

from configs.setup_hosted_ci import download, unpack


@contextmanager
def served(payload):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/tool")
                self.end_headers()
            elif self.path == "/tool":
                self.send_response(200)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            else:
                self.send_error(404)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=lambda: server.serve_forever(poll_interval=0.01))
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


class HostedToolDownloads(unittest.TestCase):
    def test_download_follows_redirect_and_verifies_received_bytes(self):
        payload = b"downloaded tool\x00\xff" * 100
        with tempfile.TemporaryDirectory() as directory, served(payload) as origin:
            path = Path(directory) / "tool.zip"
            download(origin + "/redirect", path, hashlib.sha256(payload).hexdigest())
            self.assertEqual(path.read_bytes(), payload)
            with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                download(origin + "/tool", path, "0" * 64)

    def test_failed_download_cannot_validate_an_existing_file(self):
        with tempfile.TemporaryDirectory() as directory, served(b"tool") as origin:
            path = Path(directory) / "tool.zip"
            path.write_bytes(b"old verified bytes")
            with self.assertRaises(subprocess.CalledProcessError):
                download(
                    origin + "/missing",
                    path,
                    hashlib.sha256(path.read_bytes()).hexdigest(),
                )

    def test_font_download_checks_git_blob_identity(self):
        payload = b"font"
        with tempfile.TemporaryDirectory() as directory, served(payload) as origin:
            path = Path(directory) / "font.otf"
            download(
                origin + "/tool",
                path,
                hashlib.sha1(b"blob 4\0font").hexdigest(),
                git_blob=True,
            )
            self.assertEqual(path.read_bytes(), payload)
            with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                download(origin + "/tool", path, "0" * 40, git_blob=True)

    def test_templates_extract_only_selected_android_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "templates.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("templates/android_source.zip", b"android")
                output.writestr("templates/unneeded-desktop", b"desktop")
            unpack(archive, root / "out", ["templates/android_source.zip"])
            self.assertEqual(
                (root / "out/templates/android_source.zip").read_bytes(), b"android"
            )
            self.assertFalse((root / "out/templates/unneeded-desktop").exists())

    def test_archive_cannot_write_outside_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "bad.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("../escaped", b"bad")
            with self.assertRaisesRegex(RuntimeError, "Unsafe archive"):
                unpack(archive, root / "out")
            self.assertFalse((root / "escaped").exists())
