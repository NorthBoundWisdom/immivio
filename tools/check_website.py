"""Check the static bilingual website without browser automation or external requests."""

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json
import hashlib
import re
import struct
import xml.etree.ElementTree as ET

ORIGIN = "https://northboundwisdom.github.io/immivio/"
REPO_BLOB = "https://github.com/NorthBoundWisdom/immivio/blob/main/"

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path, self.ids, self.links = path, set(), []
        self.language, self.headings = "", 0
        self.canonical, self.alternates, self.locales = "", {}, []
        self.metadata, self.titles, self.structured = {}, [], []
        self.capture = None
        self.feed(path.read_text(encoding="utf-8"))

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "meta":
            key = values.get("name") or values.get("property")
            if key:
                assert key not in self.metadata, f"{self.path}: duplicate meta {key}"
                self.metadata[key] = values.get("content", "")
        if tag == "title":
            self.titles.append("")
            self.capture = "title"
        if tag == "script" and values.get("type") == "application/ld+json":
            self.capture = "json"
            self.json_text = ""
        if "id" in values:
            assert (
                values["id"] not in self.ids
            ), f"{self.path}: duplicate ID {values['id']}"
            self.ids.add(values["id"])
        if tag == "link" and values.get("rel") == "canonical":
            self.canonical = values.get("href", "")
        if tag == "link" and values.get("rel") == "alternate":
            self.alternates[values.get("hreflang")] = values.get("href")
        if tag == "a" and "locale" in values.get("class", "").split():
            self.locales.append(values.get("href"))
        if tag == "html":
            self.language = values.get("lang")
        if tag == "h1":
            self.headings += 1
        if tag == "img":
            assert "alt" in values, f"{self.path}: image missing alt"
        for field in ["src", "href"]:
            if values.get(field):
                self.links.append(values[field])

    def handle_data(self, data):
        if self.capture == "title":
            self.titles[-1] += data
        elif self.capture == "json":
            self.json_text += data

    def handle_endtag(self, tag):
        if tag == "title":
            self.capture = None
        elif tag == "script" and self.capture == "json":
            self.structured.append(json.loads(self.json_text))
            self.capture = None


def main():
    pages = {path.resolve(): Page(path) for path in SITE.rglob("*.html")}
    routes = {"index.html", "guide/index.html", "updates/index.html"}
    expected = routes | {"zh/" + route for route in routes}
    assert {str(path.relative_to(SITE)) for path in pages} == expected
    sitemap = ET.parse(SITE / "sitemap.xml")
    locations = {
        node.text
        for node in sitemap.findall(
            ".//{http://www.sitemaps.org/schemas/sitemap/0.9}loc"
        )
    }
    assert locations == {
        ORIGIN + route.removesuffix("index.html") for route in expected
    }
    for path, page in pages.items():
        assert page.headings == 1, f"{path}: expected one page heading"
        assert page.language == (
            "zh-CN" if "zh" in path.relative_to(SITE).parts else "en"
        )
        relative = str(path.relative_to(SITE))
        zh = relative.startswith("zh/")
        counterpart = relative[3:] if zh else "zh/" + relative
        assert page.canonical == ORIGIN + relative.removesuffix(
            "index.html"
        ), f"{path}: wrong canonical URL"
        assert (
            page.alternates.get(page.language) == page.canonical
        ), f"{path}: missing self language alternate"
        assert len(page.titles) == 1 and page.titles[0].strip()
        assert page.metadata.get("description", "").strip()
        for prefix in ("og:", "twitter:"):
            assert page.metadata.get(prefix + "title") == page.titles[0]
            assert (
                page.metadata.get(prefix + "description")
                == page.metadata["description"]
            )
        assert page.metadata.get("og:url") == page.canonical
        assert "noindex" not in page.metadata.get("robots", "").lower()
        assert len(page.structured) == 1
        graph = page.structured[0]
        assert graph["@context"] == "https://schema.org"
        entries = graph["@graph"]
        web_pages = [entry for entry in entries if entry["@type"] == "WebPage"]
        assert len(web_pages) == 1
        assert web_pages[0]["url"] == page.canonical
        assert web_pages[0]["inLanguage"] == page.language
        assert web_pages[0]["name"] == page.titles[0]
        assert web_pages[0]["description"] == page.metadata["description"]
        apps = [entry for entry in entries if entry["@type"] == "SoftwareApplication"]
        if relative in ("index.html", "zh/index.html"):
            assert len(apps) == 1
            assert (
                apps[0]["name"] == "Immivio" and apps[0]["isAccessibleForFree"] is True
            )
            assert apps[0]["offers"]["price"] == "0"
        assert page.alternates.get(
            "en" if zh else "zh-CN"
        ) == ORIGIN + counterpart.removesuffix(
            "index.html"
        ), f"{path}: wrong language alternate"
        assert len(page.locales) == 1
        assert (path.parent / page.locales[0] / "index.html").resolve() == (
            SITE / counterpart
        ).resolve(), f"{path}: language switch changes page"
        for link in page.links:
            if link.startswith(REPO_BLOB):
                repo_path = (
                    ROOT / unquote(link[len(REPO_BLOB) :].split("#")[0])
                ).resolve()
                assert (
                    repo_path.is_relative_to(ROOT) and repo_path.is_file()
                ), f"{path}: missing repository document {link}"
            uri = urlsplit(link)
            if uri.scheme or uri.netloc:
                continue
            target = (path.parent / unquote(uri.path)).resolve() if uri.path else path
            if target.is_dir():
                target /= "index.html"
            assert target.is_relative_to(
                SITE
            ), f"{path}: local link escapes website: {link}"
            assert target.is_file(), f"{path}: missing target {link}"
            if uri.fragment and target.suffix == ".html":
                assert (
                    unquote(uri.fragment) in pages[target].ids
                ), f"{path}: missing anchor {link}"
    release = json.loads((SITE / "assets/releases.json").read_text())
    assert release["html_url"].startswith(
        "https://github.com/NorthBoundWisdom/immivio/releases"
    )
    # Until the first branded release, the site links to current development builds.
    assert len(release["assets"]) in [0, 3]
    if release["assets"]:
        assert release["tag_name"]
        for platform in ["QUEST", "PICO", "OpenXR"]:
            matches = [
                asset
                for asset in release["assets"]
                if re.fullmatch(
                    rf"Immivio-{platform}-[0-9][A-Za-z0-9._-]*-release-\d{{8}}\.apk",
                    asset["name"],
                    re.I,
                )
            ]
            assert len(matches) == 1, f"Missing or ambiguous APK: {platform}"
            assert matches[0]["size"] > 0
            assert matches[0]["browser_download_url"].startswith(
                "https://github.com/NorthBoundWisdom/immivio/releases/download/"
            )
    for name in ["playback", "settings", "display"]:
        data = (SITE / f"assets/screenshots/{name}.png").read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(
            ">II", data[16:24]
        ) == (1920, 1080)
        assert (
            len(data) > 100000
        ), f"{name}: unexpectedly small screenshot; inspect for blank playback"
    capture = json.loads((SITE / "assets/screenshots/capture.json").read_text())
    for shot in capture["screenshots"]:
        assert (
            hashlib.sha256(
                (SITE / "assets/screenshots" / shot["file"]).read_bytes()
            ).hexdigest()
            == shot["sha256"]
        )
    print(
        f"Website checks passed: {len(pages)} pages, 2 languages, search metadata and structured data, single-edition downloads, 3 emulator screenshots."
    )


if __name__ == "__main__":
    main()
