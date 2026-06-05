#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXT_DIR = ROOT / "editors" / "vscode-oren"


def load_json(rel: str):
    path = EXT_DIR / rel
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"verify_vscode_oren_extension: {message}")


def main() -> int:
    package = load_json("package.json")
    require(package.get("main") == "./src/extension.js", "package main must point at src/extension.js")
    contributes = package.get("contributes", {})
    languages = contributes.get("languages", [])
    grammars = contributes.get("grammars", [])
    require(any(lang.get("id") == "oren" and ".oren" in lang.get("extensions", []) for lang in languages), "missing .oren language contribution")
    require(any(grammar.get("language") == "oren" and grammar.get("scopeName") == "source.oren" for grammar in grammars), "missing source.oren grammar contribution")
    require("vscode-languageclient" in package.get("dependencies", {}), "missing vscode-languageclient dependency")

    grammar = load_json("syntaxes/oren.tmLanguage.json")
    require(grammar.get("scopeName") == "source.oren", "grammar scopeName mismatch")
    require(bool(grammar.get("patterns")), "grammar must define patterns")
    repository = grammar.get("repository", {})
    for name in ("comments", "strings", "keywords", "declarations", "numbers"):
        require(name in repository, f"grammar missing {name} repository")

    config = load_json("language-configuration.json")
    require(config.get("comments", {}).get("lineComment") == "//", "language config missing line comments")
    require(["{", "}"] in config.get("brackets", []), "language config missing curly brackets")

    extension_js = EXT_DIR / "src" / "extension.js"
    subprocess.run(["node", "--check", str(extension_js)], check=True, cwd=ROOT)
    probe = (
        "const ext = require('./editors/vscode-oren/src/extension.js');"
        "if (typeof ext.activate !== 'function' || typeof ext.deactivate !== 'function') process.exit(2);"
        "if (ext.defaultServerCommand('/repo') !== require('path').join('/repo', process.platform === 'win32' ? 'oren-lsp.exe' : 'oren-lsp')) process.exit(3);"
    )
    subprocess.run(["node", "-e", probe], check=True, cwd=ROOT)
    print("OK: VS Code Oren extension smoke passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
