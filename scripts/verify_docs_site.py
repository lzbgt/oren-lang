#!/usr/bin/env python3
from html.parser import HTMLParser
from pathlib import Path
import sys


class LinkParser(HTMLParser):
    def __init__(self, path, missing):
        super().__init__()
        self.path = path
        self.missing = missing

    def handle_starttag(self, tag, attrs):
        if tag not in ("a", "link", "script"):
            return
        key = "href" if tag in ("a", "link") else "src"
        value = dict(attrs).get(key)
        if not value or "://" in value or value.startswith("#") or value.startswith("mailto:"):
            return
        target = (self.path.parent / value.split("#", 1)[0]).resolve()
        if not target.exists():
            self.missing.append((str(self.path), value))


def main():
    root = Path("docs/site")
    required = [
        root / "index.html",
        root / "assets/site.css",
        root / "assets/site.js",
        root / "assets/search-index.js",
    ]
    missing_required = [str(p) for p in required if not p.exists()]
    if missing_required:
        print("missing required docs-site files:")
        for p in missing_required:
            print(p)
        return 1
    missing_links = []
    for path in root.rglob("*.html"):
        LinkParser(path, missing_links).feed(path.read_text(encoding="utf-8"))
    if missing_links:
        print("missing docs-site links:")
        for path, link in missing_links[:50]:
            print(f"{path}: {link}")
        return 1
    print("docs site verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
