import re
from typing import Dict, List

from status_snapshot_lib import snapshot_from_status


SECTION_ORDER = (
    "production_readiness_gap",
    "backend_readiness",
    "feature_readiness_gaps",
)

SECTION_TITLES = {
    "production_readiness_gap": "Production readiness gap",
    "backend_readiness": "Backend readiness",
    "feature_readiness_gaps": "Feature readiness gaps",
}

LABEL_PATTERNS = (
    re.compile(r"^\*\*(.+?)\*\*:\s*(.+)$"),
    re.compile(r"^`(.+?)`:\s*(.+)$"),
    re.compile(r"^(.+?):\s*(.+)$"),
)


def parse_item(item: str, index: int) -> Dict[str, str]:
    if not item:
        return {
            "name": f"item-{index}",
            "notes": "",
            "raw": item,
        }
    lines = item.splitlines()
    head = lines[0].strip()
    tail_lines = lines[1:]
    tail = "\n".join([line.rstrip() for line in tail_lines]).rstrip()
    for pattern in LABEL_PATTERNS:
        match = pattern.match(head)
        if match:
            notes = match.group(2).strip()
            if tail:
                notes = f"{notes}\n{tail}"
            return {
                "name": match.group(1).strip(),
                "notes": notes,
                "raw": item,
            }
    return {
        "name": f"item-{index}",
        "notes": f"{head}\n{tail}".rstrip(),
        "raw": item,
    }


def rows_from_items(items: List[str]) -> List[Dict[str, str]]:
    return [parse_item(item, idx) for idx, item in enumerate(items, start=1)]


def matrix_from_sections(sections: Dict[str, Dict[str, List[str]]]) -> Dict[str, List[Dict[str, str]]]:
    matrix: Dict[str, List[Dict[str, str]]] = {}
    for key in SECTION_ORDER:
        matrix[key] = rows_from_items(sections.get(key, {}).get("items", []))
    return matrix


def matrix_from_status(path: str) -> Dict[str, List[Dict[str, str]]]:
    sections = snapshot_from_status(path)
    return matrix_from_sections(sections)


def row_identity(row: Dict[str, str]) -> str:
    raw = row.get("raw")
    if raw:
        return raw
    name = row.get("name", "").strip()
    notes = row.get("notes", "").strip()
    if name and notes:
        return f"{name}: {notes}"
    return name or notes
