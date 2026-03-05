import os
from typing import Dict, List, Tuple


SECTION_MATCHES = {
    "production_readiness_gap": "production readiness gap",
    "backend_readiness": "backend readiness",
    "feature_readiness_gaps": "feature readiness gaps",
}


def load_lines(path: str) -> List[str]:
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def is_heading(line: str) -> bool:
    return line.startswith("#") and line.lstrip().startswith("#")


def heading_text(line: str) -> str:
    return line.lstrip("# ").strip().lower()


def collect_section(lines: List[str], header_match: str) -> Tuple[str, List[str]]:
    current_title = ""
    collecting = False
    items: List[str] = []
    for line in lines:
        if is_heading(line):
            title = heading_text(line)
            if header_match in title:
                collecting = True
                current_title = line.strip().lstrip("#").strip()
                continue
            if collecting:
                break
        if collecting:
            striped = line.strip()
            if striped.startswith("- "):
                items.append(striped[2:])
    return current_title, items


def snapshot_from_lines(lines: List[str]) -> Dict[str, Dict[str, List[str]]]:
    payload: Dict[str, Dict[str, List[str]]] = {}
    for key, match in SECTION_MATCHES.items():
        title, items = collect_section(lines, match)
        payload[key] = {
            "title": title or match,
            "items": items,
        }
    return payload


def snapshot_from_status(path: str) -> Dict[str, Dict[str, List[str]]]:
    return snapshot_from_lines(load_lines(path))
