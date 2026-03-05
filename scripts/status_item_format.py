from typing import Any, Dict, List


def items_from_section(section: Dict[str, Any]) -> List[str]:
    items = section.get("items")
    if isinstance(items, list) and all(isinstance(item, str) for item in items):
        return list(items)
    structured = section.get("items_structured")
    if isinstance(structured, list):
        out: List[str] = []
        for entry in structured:
            if not isinstance(entry, dict):
                continue
            raw = entry.get("raw")
            if isinstance(raw, str) and raw:
                out.append(raw)
                continue
            head = entry.get("head")
            if isinstance(head, str) and head:
                out.append(head)
        return out
    return []


def format_multiline_item(item: str) -> List[str]:
    if item is None:
        return ["- (empty)"]
    text = str(item)
    if not text:
        return ["- (empty)"]
    lines = text.splitlines()
    if not lines:
        return ["- (empty)"]
    out = [f"- {lines[0]}"]
    for line in lines[1:]:
        if line.startswith((" ", "\t")):
            out.append(line)
        else:
            out.append(f"  {line}")
    return out
