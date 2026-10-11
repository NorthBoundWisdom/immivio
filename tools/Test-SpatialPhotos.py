"""Compare production HEIF eye-selection copies with an independent libheif decode.

Requires pillow-heif on the host. Does not run Android ImageDecoder or validate XR.
The copies and per-file JSON records come from HeifPhotoInfoTest with
THRU3D_SPATIAL_FIXTURES and THRU3D_HEIF_PROBE_OUTPUT set.
"""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", required=True, type=Path)
    parser.add_argument("--probe", type=Path, default=Path("build/output/spatial-photos/primary-probe"))
    parser.add_argument("--output", type=Path, default=Path("build/output/spatial-photos/reference-verification.json"))
    parser.add_argument("--decoder-root", type=Path, help="Optional isolated host package directory")
    args = parser.parse_args()
    if args.decoder_root:
        import sys
        sys.path.insert(0, str(args.decoder_root.resolve()))
    import pillow_heif

    results = []
    for source in sorted(args.samples.iterdir()):
        if source.suffix.lower() not in (".heic", ".heif") or source.name.startswith("control-"):
            continue
        original = pillow_heif.open_heif(source, convert_hdr_to_8bit=True)
        groups = [g for g in original.info.get("entity_groups", []) if g["type"] == "ster"]
        if len(groups) != 1:
            raise ValueError(f"{source.name}: no unambiguous native stereo group")
        group = groups[0]
        metadata = json.loads((args.probe / (source.stem + ".json")).read_text(encoding="utf-8"))
        if [metadata["left_item"], metadata["right_item"]] != group["entities"]:
            raise ValueError(f"{source.name}: production eye IDs differ from libheif")
        indices = group["images"]
        if original[indices[0]].data == original[indices[1]].data:
            raise ValueError(f"{source.name}: the two eyes are identical")
        for eye, index in zip(("left", "right"), indices):
            selected = pillow_heif.open_heif(args.probe / (source.stem + "-" + eye + ".heic"), convert_hdr_to_8bit=True)
            if selected.data != original[index].data:
                raise ValueError(f"{source.name}: {eye} selection pixels differ")
            if selected.size != (metadata["width"], metadata["height"]):
                raise ValueError(f"{source.name}: transformed dimensions differ")
        results.append({
            "file": source.name,
            "left_item": metadata["left_item"], "right_item": metadata["right_item"],
            "eye_size": [metadata["width"], metadata["height"]], "disparity": metadata["disparity"],
            "primary_selection_pixels_equal": True, "distinct_eyes": True,
            "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        })
    if len(results) < 5:
        raise ValueError("At least five different native spatial originals are required")
    report = {"scope": "HEIF metadata and reference-decoded eye selection; Android/XR not covered", "files": results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Spatial reference: {len(results)} originals, {len(results) * 2} matching eye views; Android/XR still unverified")


if __name__ == "__main__":
    main()
