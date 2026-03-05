from typing import Any, Dict, List


def html_escape(value: Any) -> str:
    if value is None:
        return "-"
    text = str(value)
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#x27;")
    )


def status_css() -> str:
    return "\n".join(
        [
            ".faq-block { border: 1px solid #e0e0e0; padding: 12px; border-radius: 6px; margin-bottom: 10px; background: #fff; }",
            ".faq-question { font-weight: bold; margin-bottom: 6px; }",
            ".faq-item-head { font-weight: 500; }",
            ".faq-item-cont { margin-left: 14px; color: #555; font-size: 12px; }",
            ".status-block { border: 1px solid #e0e0e0; padding: 12px; border-radius: 6px; margin-bottom: 12px; background: #fff; }",
            ".status-title { font-weight: bold; margin-bottom: 8px; }",
            ".status-item-head { font-weight: 500; }",
            ".status-item-cont { margin-left: 14px; color: #555; font-size: 12px; }",
        ]
    )


def _item_lines_from_structured(item: Any) -> List[str]:
    if not isinstance(item, dict):
        return []
    lines = item.get("lines")
    if isinstance(lines, list) and lines:
        return [str(line) for line in lines]
    raw = item.get("raw")
    if isinstance(raw, str) and raw:
        return raw.splitlines()
    head = item.get("head")
    if isinstance(head, str) and head:
        return [head]
    return []


def _render_item_lines(lines: List[str], cont_class: str, head_class: str) -> str:
    if not lines:
        return ""
    head = html_escape(lines[0])
    cont = "".join(
        f"<div class='{cont_class}'>{html_escape(line)}</div>"
        for line in lines[1:]
    )
    return f"<li><div class='{head_class}'>{head}</div>{cont}</li>"


def render_status_faq(data: Dict[str, Any]) -> str:
    if not data:
        return ""
    questions = data.get("questions")
    if not isinstance(questions, list) or not questions:
        return ""
    blocks: List[str] = []
    for entry in questions:
        if not isinstance(entry, dict):
            continue
        question = html_escape(entry.get("question", "-"))
        structured = entry.get("items_structured")
        items_html = ""
        if isinstance(structured, list) and structured:
            rendered_items = []
            for item in structured:
                lines = _item_lines_from_structured(item)
                rendered = _render_item_lines(lines, "faq-item-cont", "faq-item-head")
                if rendered:
                    rendered_items.append(rendered)
            if rendered_items:
                items_html = "<ul>" + "".join(rendered_items) + "</ul>"
        if not items_html:
            items = entry.get("items", [])
            if isinstance(items, list) and items:
                rendered_items = []
                for item in items:
                    lines = str(item).splitlines()
                    rendered_items.append(
                        _render_item_lines(lines, "faq-item-cont", "faq-item-head")
                    )
                items_html = "<ul>" + "".join(rendered_items) + "</ul>"
        if not items_html:
            items_html = "<div class='meta'>(no items)</div>"
        blocks.append(
            "<div class='faq-block'>"
            f"<div class='faq-question'>{question}</div>"
            f"{items_html}</div>"
        )
    if not blocks:
        return ""
    return "<h2>Status FAQ</h2>\n" + "".join(blocks)


def render_status_snapshot(data: Dict[str, Any]) -> str:
    if not data:
        return ""
    sections = data.get("sections")
    if not isinstance(sections, dict) or not sections:
        return ""

    def section_items(section: Dict[str, Any]) -> List[str]:
        structured = section.get("items_structured")
        if isinstance(structured, list) and structured:
            items = []
            for entry in structured:
                if not isinstance(entry, dict):
                    continue
                lines = entry.get("lines")
                if isinstance(lines, list) and lines:
                    items.append("\n".join(str(line) for line in lines))
                    continue
                raw = entry.get("raw")
                if isinstance(raw, str) and raw:
                    items.append(raw)
            if items:
                return items
        items = section.get("items")
        if isinstance(items, list) and items:
            return [str(item) for item in items]
        return []

    order = ("production_readiness_gap", "backend_readiness", "feature_readiness_gaps")
    blocks: List[str] = []
    for key in order:
        section = sections.get(key)
        if not isinstance(section, dict):
            continue
        title = html_escape(section.get("title") or key)
        items = section_items(section)
        if items:
            rendered = []
            for item in items:
                lines = str(item).splitlines()
                rendered.append(
                    _render_item_lines(lines, "status-item-cont", "status-item-head")
                )
            items_html = "<ul>" + "".join(rendered) + "</ul>"
        else:
            items_html = "<div class='meta'>(no items)</div>"
        blocks.append(
            "<div class='status-block'>"
            f"<div class='status-title'>{title}</div>"
            f"{items_html}</div>"
        )
    if not blocks:
        return ""
    return "<h2>Status Snapshot</h2>\n" + "".join(blocks)


def render_status_matrix(data: Dict[str, Any]) -> str:
    if not data:
        return ""
    sections = data.get("sections") if isinstance(data.get("sections"), dict) else data
    if not isinstance(sections, dict) or not sections:
        return ""

    def render_notes_lines(lines: List[str]) -> str:
        if not lines:
            return "-"
        head = html_escape(lines[0])
        cont = "".join(
            f"<div class='status-item-cont'>{html_escape(line)}</div>"
            for line in lines[1:]
        )
        return f"<div class='status-item-head'>{head}</div>{cont}"

    def notes_lines(row: Dict[str, Any]) -> List[str]:
        lines = row.get("notes_lines")
        if isinstance(lines, list) and lines:
            return [str(line) for line in lines]
        notes = row.get("notes")
        if isinstance(notes, str) and notes:
            return notes.splitlines()
        raw = row.get("raw")
        if isinstance(raw, str) and raw:
            return raw.splitlines()
        raw_lines = row.get("raw_lines")
        if isinstance(raw_lines, list) and raw_lines:
            return [str(line) for line in raw_lines]
        return []

    order = ("production_readiness_gap", "backend_readiness", "feature_readiness_gaps")
    title_map = {
        "production_readiness_gap": "Production readiness gap",
        "backend_readiness": "Backend readiness",
        "feature_readiness_gaps": "Feature readiness gaps",
    }
    blocks: List[str] = []
    for key in order:
        rows = sections.get(key, [])
        if not isinstance(rows, list) or not rows:
            continue
        title = html_escape(title_map.get(key, key))
        body_rows = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            name = html_escape(row.get("name", "-"))
            notes = render_notes_lines(notes_lines(row))
            body_rows.append(f"<tr><td>{name}</td><td>{notes}</td></tr>")
        if not body_rows:
            continue
        table = (
            "<table>"
            "<thead><tr><th>Name</th><th>Notes</th></tr></thead>"
            f"<tbody>{''.join(body_rows)}</tbody></table>"
        )
        blocks.append(
            "<div class='status-block'>"
            f"<div class='status-title'>{title}</div>"
            f"{table}</div>"
        )
    if not blocks:
        return ""
    return "<h2>Status Matrix</h2>\n" + "".join(blocks)


def _trunc_structured_item(total: int) -> Dict[str, Any]:
    label = f"(truncated, {total} total)"
    return {"raw": label, "lines": [label], "head": label}


def _limit_list(items: List[Any], max_items: int) -> List[Any]:
    if max_items <= 0 or len(items) <= max_items:
        return items
    return items[:max_items] + [f"(truncated, {len(items)} total)"]


def _limit_structured(items: List[Any], max_items: int) -> List[Any]:
    if max_items <= 0 or len(items) <= max_items:
        return items
    return items[:max_items] + [_trunc_structured_item(len(items))]


def limit_status_faq(data: Dict[str, Any], max_items: int) -> Dict[str, Any]:
    if not data or max_items <= 0:
        return data
    questions = data.get("questions")
    if not isinstance(questions, list):
        return data
    trimmed = []
    for entry in questions:
        if not isinstance(entry, dict):
            continue
        out = dict(entry)
        structured = entry.get("items_structured")
        items = entry.get("items")
        if isinstance(structured, list):
            out["items_structured"] = _limit_structured(list(structured), max_items)
        elif isinstance(items, list):
            out["items"] = _limit_list(list(items), max_items)
        trimmed.append(out)
    return {"questions": trimmed}


def limit_status_snapshot(data: Dict[str, Any], max_items: int) -> Dict[str, Any]:
    if not data or max_items <= 0:
        return data
    sections = data.get("sections")
    if not isinstance(sections, dict):
        return data
    trimmed_sections: Dict[str, Any] = {}
    for key, section in sections.items():
        if not isinstance(section, dict):
            continue
        out = dict(section)
        structured = section.get("items_structured")
        items = section.get("items")
        if isinstance(structured, list):
            out["items_structured"] = _limit_structured(list(structured), max_items)
        elif isinstance(items, list):
            out["items"] = _limit_list(list(items), max_items)
        trimmed_sections[key] = out
    return {"sections": trimmed_sections}


def limit_status_matrix(data: Dict[str, Any], max_items: int) -> Dict[str, Any]:
    if not data or max_items <= 0:
        return data
    sections = data.get("sections") if isinstance(data.get("sections"), dict) else data
    if not isinstance(sections, dict):
        return data
    trimmed_sections: Dict[str, Any] = {}
    for key, rows in sections.items():
        if not isinstance(rows, list):
            continue
        if len(rows) <= max_items:
            trimmed_sections[key] = rows
            continue
        trunc_row = {"name": f"(truncated, {len(rows)} total)", "notes": "", "notes_lines": []}
        trimmed_sections[key] = rows[:max_items] + [trunc_row]
    return {"sections": trimmed_sections}
