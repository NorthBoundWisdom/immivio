"""Decode aapt2 xmltree manifests and enforce the external playback export policy."""
import json
import re
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
ACTIVITY = "org.vrpassthroughplayer.plugin.ExternalPlaybackActivity"


def verify_tree(root):
    if root.tag != "manifest":
        raise ValueError("Expected an Android manifest root")
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



def verify(path):
    verify_tree(ET.parse(path).getroot())


def _qualified(name, namespaces):
    if ":" not in name:
        return name
    prefix, local = name.rsplit(":", 1)
    uri = namespaces.get(prefix)
    if uri is None and prefix.startswith(("http://", "https://")):
        uri = prefix
    if uri is None or not local:
        raise ValueError("Unknown manifest namespace")
    return "{" + uri + "}" + local


def _value(text):
    text = text.strip()
    typed = re.match(r"^\(type (0x[0-9a-fA-F]+)\)(.*)$", text)
    kind = None
    if typed:
        kind = int(typed[1], 16)
        text = typed[2].strip()
    if text.startswith('"'):
        value, end = json.JSONDecoder().raw_decode(text)
        if text[end:] and not text[end:].startswith(" (Raw: "):
            raise ValueError("Malformed manifest string")
        return value
    if kind == 0x12:
        return "true" if int(text, 0) != 0 else "false"
    if kind in (0x10, 0x11):
        return str(int(text, 0))
    if not text or " (Raw: " in text:
        raise ValueError("Malformed manifest attribute")
    return text


def parse_xmltree(text):
    """Reconstruct elements, attributes and namespaces by depth, not matching policy fragments.

    Accept both prefixed and full-URI aapt2 attribute names, resource ID suffixes,
    and typed scalar values. Unknown records, duplicate attributes and multiple
    roots fail closed rather than silently disappearing from the policy input.
    """
    namespaces = {}
    stack = []
    root = None
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        if "\t" in line[:len(line) - len(line.lstrip())]:
            raise ValueError(f"Invalid manifest indentation at line {number}")
        indent = len(line) - len(line.lstrip(" "))
        record = line.strip()
        if record.startswith("N: "):
            match = re.fullmatch(r"N: ([A-Za-z_][A-Za-z0-9_.-]*)=(\S+?)(?: \(line=\d+\))?", record)
            if not match:
                raise ValueError(f"Invalid manifest namespace at line {number}")
            if match[1] in namespaces and namespaces[match[1]] != match[2]:
                raise ValueError("Manifest namespace redefinition")
            namespaces[match[1]] = match[2]
        elif record.startswith("E: "):
            match = re.fullmatch(r"E: ([^\s]+)(?: \(line=\d+\))?", record)
            if not match:
                raise ValueError(f"Invalid manifest element at line {number}")
            while stack and stack[-1][0] >= indent:
                stack.pop()
            element = ET.Element(_qualified(match[1], namespaces))
            if stack:
                stack[-1][1].append(element)
            elif root is None:
                root = element
            else:
                raise ValueError("Multiple manifest roots")
            stack.append((indent, element))
        elif record.startswith("A: "):
            if not stack or indent <= stack[-1][0]:
                raise ValueError(f"Manifest attribute has no owner at line {number}")
            name, separator, value = record[3:].partition("=")
            if not separator:
                raise ValueError(f"Invalid manifest attribute at line {number}")
            name = re.sub(r"\(0x[0-9a-fA-F]+\)$", "", name)
            qualified = _qualified(name, namespaces)
            if qualified in stack[-1][1].attrib:
                raise ValueError("Duplicate manifest attribute")
            stack[-1][1].set(qualified, _value(value))
        else:
            raise ValueError(f"Unsupported manifest record at line {number}")
    if root is None or root.tag != "manifest":
        raise ValueError("Missing manifest root")
    return root


def verify_xmltree(text):
    root = parse_xmltree(text)
    verify_tree(root)
    return root
