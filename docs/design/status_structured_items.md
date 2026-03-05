# Status Structured Items (Snapshot / FAQ / Matrix)

## Goals

- Preserve multi-line STATUS bullets in machine-readable outputs.
- Provide line-level structure for consumers without breaking existing JSON.
- Keep markdown outputs unchanged.

## Non-goals

- No changes to STATUS.md authoring conventions.
- No changes to diff semantics or ordering.
- No new external dependencies.

## Data model (additive)

### Snapshot sections

Each section keeps the existing `items` array and adds `items_structured`:

```json
{
  "title": "Backend readiness (rolling snapshot)",
  "items": [
    "**C backend**: bootstrap path only.\n  continuation line"
  ],
  "items_structured": [
    {
      "raw": "**C backend**: bootstrap path only.\n  continuation line",
      "lines": [
        "**C backend**: bootstrap path only.",
        "  continuation line"
      ],
      "head": "**C backend**: bootstrap path only.",
      "continuations": [
        "  continuation line"
      ],
      "continuations_stripped": [
        "continuation line"
      ],
      "has_nested_bullets": false
    }
  ]
}
```

### FAQ questions

Each question keeps `items` and adds `items_structured` (same structure as snapshot items).

### Matrix rows

Matrix rows add `raw_lines` and `notes_lines` (both arrays of strings) derived from the
existing `raw` and `notes` fields.

## Rollout

- Add `items_structured` to snapshot + FAQ JSON outputs.
- Add line arrays to matrix JSON output.
- Diff tools prefer `items` but can fall back to `items_structured[].raw`.
- Update smoke tests to cover continuation lines.
