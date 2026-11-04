"""Check the shared external playback policy in a merged XML or compiled APK manifest dump."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from configs.android_manifest import ACTIVITY, verify, verify_xmltree

if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--xmltree":
        verify_xmltree(Path(sys.argv[2]).read_text(encoding="utf-8"))
    elif len(sys.argv) == 2:
        verify(Path(sys.argv[1]))
    else:
        raise SystemExit("Usage: check_external_playback_manifest.py [--xmltree] <manifest>")
    print("Final manifest: narrow video/local associations verified; no BROWSABLE or APK installation permission")
