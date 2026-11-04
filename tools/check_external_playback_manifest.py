"""Verify external video associations in the final, merged Android manifest."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
ACTIVITY = "org.vrpassthroughplayer.plugin.ExternalPlaybackActivity"


def verify(path):
    root = ET.parse(path).getroot()
    activities = root.findall("./application/activity")
    entries = [item for item in activities if item.get(ANDROID + "name") == ACTIVITY]
    if len(entries) != 1 or entries[0].get(ANDROID + "exported") != "true":
        raise ValueError("Exactly one exported external playback entry is required")
    expected = {
        ("android.intent.action.VIEW", frozenset({"http", "https"}), frozenset({"video/*"})),
        ("android.intent.action.VIEW", frozenset({"content", "file"}), frozenset({"video/*", "application/octet-stream"})),
        ("android.intent.action.SEND", frozenset(), frozenset({"video/*", "application/octet-stream"})),
    }
    actual = []
    for group in entries[0].findall("intent-filter"):
        actions = [node.get(ANDROID + "name") for node in group.findall("action")]
        categories = {node.get(ANDROID + "name") for node in group.findall("category")}
        if len(actions) != 1 or categories != {"android.intent.category.DEFAULT"}:
            raise ValueError("External playback must have one action and DEFAULT only, without BROWSABLE")
        schemes = frozenset(node.get(ANDROID + "scheme") for node in group.findall("data") if node.get(ANDROID + "scheme"))
        mimes = frozenset(node.get(ANDROID + "mimeType") for node in group.findall("data") if node.get(ANDROID + "mimeType"))
        actual.append((actions[0], schemes, mimes))
    if len(actual) != 3 or set(actual) != expected:
        raise ValueError("External video filters differ from the narrow network/local/SEND contract")
    if any(item.get(ANDROID + "name") == "android.permission.REQUEST_INSTALL_PACKAGES" for item in root.findall("uses-permission")):
        raise ValueError("The player must not request APK installation permission")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
    print("Final merged manifest: narrow video/local associations verified; no BROWSABLE or APK installation permission")
