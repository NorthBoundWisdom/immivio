"""Generate original, reproducible stereo-alignment MP4 fixtures (Pillow + ffmpeg).

No downloaded footage is needed. Output is disposable; this source is the master.
Run: python tools/Generate-StereoFixtures.py
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

EYE = (800, 400)
DX, DY = 24, 8  # 3% width and 2% height, recoverable with +3.00%, +2.00%.
CASES = [
    ("01_control_flat_LRF", "sbs", (0, 0), "Normal control", False, False),
    ("02_offset_flat_LRF", "sbs", (DX, DY), "Misaligned SBS", False, False),
    ("03_offset_flat_TBF", "tb", (DX, DY), "Misaligned TB", False, False),
    ("04_reversed_flat_LRF", "sbs", (0, 0), "Reversed eye order", True, False),
    ("05_baked_ghost_flat_LRF", "sbs", (0, 0), "Baked-in ghosting", False, True),
]


def shift(image, x, y):
    result = Image.new("RGB", EYE, "#101a28")
    result.paste(image, (x, y))
    return result


def eye_frame(index, frame, fps, title, font):
    image = Image.new("RGB", EYE, "#101a28")
    draw = ImageDraw.Draw(image)
    for x in range(40, EYE[0], 40):
        draw.line((x, 55, x, 370), fill="#263b50")
    for y in range(70, 380, 40):
        draw.line((30, y, 770, y), fill="#263b50")
    draw.text((30, 15), title, font=font, fill="#eef6ff")
    draw.text(
        (680, 15),
        "LEFT" if index == 0 else "RIGHT",
        font=font,
        fill="#6fe7bf" if index == 0 else "#fdc175",
    )
    # Central cross is on the screen plane. The two rings have opposing disparity.
    draw.line((350, 200, 450, 200), fill="white", width=3)
    draw.line((400, 150, 400, 250), fill="white", width=3)
    side = 1 if index == 0 else -1
    moving = round(math.sin(frame / fps * math.tau / 4) * 32)
    for cx, cy, radius, disparity, color in [
        (190 + moving, 190, 55, 6, "#6fe7bf"),
        (605, 220, 72, -4, "#fdc175"),
    ]:
        cx += side * disparity
        draw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius), outline=color, width=5
        )
    draw.text(
        (30, 370),
        f"{frame / fps:04.1f}s    + screen plane    green near / amber far",
        font=font,
        fill="#b8cadc",
    )
    return image


def generate(output, seconds, fps, ffmpeg):
    output.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default(size=18)
    manifest = {"eye_pixels": list(EYE), "fps": fps, "seconds": seconds, "clips": []}
    for name, layout, delta, title, reverse, baked in CASES:
        size = (800, 800) if layout == "tb" else (1600, 400)
        target = output / (name + ".mp4")
        command = [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "rawvideo",
            "-pixel_format",
            "rgb24",
            "-video_size",
            f"{size[0]}x{size[1]}",
            "-framerate",
            str(fps),
            "-i",
            "pipe:0",
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "fast",
            "-crf",
            "16",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(target),
        ]
        with subprocess.Popen(command, stdin=subprocess.PIPE) as process:
            for frame in range(round(seconds * fps)):
                left = eye_frame(0, frame, fps, title, font)
                right = shift(eye_frame(1, frame, fps, title, font), *delta)
                if baked:
                    # Both eyes already contain the duplicate. Selecting one cannot remove it.
                    left = Image.blend(left, shift(left, 24, 0), 0.42)
                    right = Image.blend(right, shift(right, 24, 0), 0.42)
                if reverse:
                    left, right = right, left
                packed = Image.new("RGB", size)
                packed.paste(left, (0, 0))
                packed.paste(right, (0, 400) if layout == "tb" else (800, 0))
                process.stdin.write(packed.tobytes())
                if frame == 0:
                    packed.save(output / (name + ".png"))
            process.stdin.close()
            if process.wait() != 0:
                raise RuntimeError("ffmpeg failed for " + name)
        manifest["clips"].append(
            {
                "file": target.name,
                "layout": layout,
                "horizontal_percent": delta[0] / EYE[0] * 100,
                "vertical_percent": delta[1] / EYE[1] * 100,
                "swap_eyes": reverse,
                "alignment_can_remove_ghost": not baked,
                "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            }
        )
        print(target)
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "build/output/stereo-view/fixtures",
    )
    parser.add_argument("--seconds", type=float, default=6)
    parser.add_argument("--fps", type=int, default=24)
    args = parser.parse_args()
    if not 0 < args.seconds <= 60 or not 1 <= args.fps <= 60:
        parser.error("Use 0 < seconds <= 60 and 1 <= fps <= 60")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        parser.error("ffmpeg is required on PATH")
    generate(args.output, args.seconds, args.fps, ffmpeg)
