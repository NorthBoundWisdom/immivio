"""Check paired background captures for visible changes (optional media dependencies)."""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def compare(folder: Path):
    results = []
    for original in sorted(folder.glob("*-original.png")):
        optimized = original.with_name(
            original.name.replace("-original.png", "-optimized.png")
        )
        with Image.open(original) as image:
            a = np.asarray(image.convert("RGB"), dtype=np.int16)
        with Image.open(optimized) as image:
            b = np.asarray(image.convert("RGB"), dtype=np.int16)
        if a.shape != b.shape:
            raise ValueError(f"Capture dimensions differ: {original.name}")
        delta = np.abs(a - b)
        over_one = int(np.any(delta > 1, axis=2).sum())
        pixels = a.shape[0] * a.shape[1]
        # Allow sparse floating-point/derivative rounding, while catching lost
        # stars, brightness changes, altered scenery or a shifted hill silhouette.
        passed = (
            int(delta.max()) <= 16
            and float(delta.mean()) <= 0.001
            and over_one / pixels <= 0.0001
        )
        results.append(
            {
                "case": original.stem.removesuffix("-original"),
                "max_channel_delta": int(delta.max()),
                "mean_channel_delta": float(delta.mean()),
                "changed_pixels": int(np.any(delta > 0, axis=2).sum()),
                "pixels_over_1": over_one,
                "total_pixels": pixels,
                "passed": passed,
            }
        )
    if not results:
        raise ValueError("No paired background captures found")
    report = {"passed": all(row["passed"] for row in results), "cases": results}
    (folder / "visual-comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    report = compare(parser.parse_args().folder)
    print(
        f"Background appearance: {len(report['cases'])} pairs, "
        f"{'passed' if report['passed'] else 'FAILED'}"
    )
    raise SystemExit(0 if report["passed"] else 1)
