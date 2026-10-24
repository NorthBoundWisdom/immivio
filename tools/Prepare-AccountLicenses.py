"""Archive license texts from the project's pinned local dependencies for the About reader."""

from pathlib import Path
from zipfile import ZipFile
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.dependencies import vendors_archive


def prepare():
    root = Path(__file__).resolve().parents[1]
    output = root / "third_party/player-licenses"
    output.mkdir(exist_ok=True)
    copies = {
        "media3.txt": root / "third_party/gradle/LICENSE.txt",
        "jcifs.txt": root / "third_party/mpv/LICENSE.LGPL",
        "panorama-notice.txt": root / "app/godot/backgrounds/NOTICE.txt",
    }
    for name, source in copies.items():
        shutil.copyfile(source, output / name)
    (output / "hands.txt").write_bytes(
        (root / "app/godot/models/hands/NOTICE.txt").read_bytes()
        + b"\n\n"
        + (root / "app/godot/models/hands/LICENSE.txt").read_bytes()
    )
    with ZipFile(vendors_archive()) as archive:
        entries = sorted(
            n for n in archive.namelist() if "LICENSE" in n and not n.endswith("/")
        )
        (output / "vendors.txt").write_bytes(
            b"\n\n".join(
                n.encode() + b"\n\n" + archive.read(n) for n in entries
            ).rstrip(b"\r\n")
            + b"\n"
        )


if __name__ == "__main__":
    prepare()
