#!/usr/bin/env python3
import json
import re
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
    patterns = grammar.get("patterns")
    require(bool(patterns), "grammar must define patterns")
    includes = [pattern.get("include") for pattern in patterns if isinstance(pattern, dict)]
    require("#imports" in includes and "#strings" in includes, "grammar must include imports and strings")
    require(includes.index("#imports") < includes.index("#strings"), "import statement patterns must run before generic strings")
    repository = grammar.get("repository", {})
    for name in ("comments", "strings", "keywords", "imports", "declarations", "numbers"):
        require(name in repository, f"grammar missing {name} repository")
    import_patterns = repository.get("imports", {}).get("patterns", [])
    import_text = json.dumps(import_patterns)
    for scope in (
        "keyword.operator.import.anonymous.oren",
        "entity.name.namespace.import.oren",
        "keyword.declaration.import.oren",
        "support.module.oren",
    ):
        require(scope in import_text, f"grammar missing import scope {scope}")
    import_regexes = [re.compile(pattern["match"]) for pattern in import_patterns if "match" in pattern]
    for source in (
        'import . "helper.oren"',
        'import math "std:math"',
        'import helper "modules/helper.oren"',
    ):
        require(any(regex.search(source) for regex in import_regexes), f"grammar import regexes do not match {source!r}")

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
