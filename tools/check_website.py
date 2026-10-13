"""Check the static bilingual website without browser automation or external requests."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json
import hashlib
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'website'

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path, self.ids, self.links = path, set(), []
        self.language, self.headings = '', 0
        self.feed(path.read_text(encoding='utf-8'))
    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if 'id' in values:
            assert values['id'] not in self.ids, f'{self.path}: duplicate ID {values["id"]}'
            self.ids.add(values['id'])
        if tag == 'html': self.language = values.get('lang')
        if tag == 'h1': self.headings += 1
        if tag == 'img': assert 'alt' in values, f'{self.path}: image missing alt'
        for field in ['src', 'href']:
            if values.get(field): self.links.append(values[field])


def main():
    pages = {path.resolve(): Page(path) for path in SITE.rglob('*.html')}
    assert len(pages) >= 4
    for path, page in pages.items():
        assert page.headings == 1, f'{path}: expected one page heading'
        assert page.language == ('zh-CN' if 'zh' in path.relative_to(SITE).parts else 'en')
        for link in page.links:
            uri = urlsplit(link)
            if uri.scheme or uri.netloc: continue
            target = (path.parent / unquote(uri.path)).resolve() if uri.path else path
            if target.is_dir(): target /= 'index.html'
            assert target.is_relative_to(SITE), f'{path}: local link escapes website: {link}'
            assert target.is_file(), f'{path}: missing target {link}'
            if uri.fragment and target.suffix == '.html':
                assert unquote(uri.fragment) in pages[target].ids, f'{path}: missing anchor {link}'
    release = json.loads((SITE / 'assets/releases.json').read_text())
    assert release['tag_name'] and release['html_url'].startswith('https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases/')
    for platform in ['QUEST', 'PICO', 'OpenXR']:
        for edition in ['ai', 'noai']:
            matches = [asset for asset in release['assets'] if re.fullmatch(rf'Thru3D-{platform}-.+-{edition}-release-.+\.apk', asset['name'], re.I)]
            assert len(matches) == 1, f'Missing or ambiguous APK: {platform}/{edition}'
            assert matches[0]['size'] > 0
            assert matches[0]['browser_download_url'].startswith('https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases/download/')
    for name in ['playback', 'settings', 'display']:
        data = (SITE / f'assets/screenshots/{name}.png').read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', data[16:24]) == (1920, 1080)
        assert len(data) > 100000, f'{name}: unexpectedly small screenshot; inspect for blank playback'
    capture = json.loads((SITE / 'assets/screenshots/capture.json').read_text())
    for shot in capture['screenshots']:
        assert hashlib.sha256((SITE / 'assets/screenshots' / shot['file']).read_bytes()).hexdigest() == shot['sha256']
    print(f'Website checks passed: {len(pages)} pages, 2 languages, 6 APK choices, 3 emulator screenshots.')

if __name__ == '__main__':
    main()
