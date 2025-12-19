# Mach-O Reference Headers (Audit-Only)

These files are **vendored for audit/reference only** so Oren’s native backend can stay:

- independent of host SDK headers at build time
- fact-based when encoding Mach-O structures and dyld bind opcodes

## Upstream Sources (pinned)

Fetched on **2025-12-19**.

### `loader.h`, `nlist.h`

- Upstream repo: `apple-oss-distributions/cctools`
- Commit (HEAD at fetch time): `920a2b45080fb9badf31bf675f03b19973f0dd4f`
- Paths:
  - `include/mach-o/loader.h` → `docs/refs/macho/loader.h`
  - `include/mach-o/nlist.h` → `docs/refs/macho/nlist.h`

Notes:
- `loader.h` contains load command IDs (e.g. `LC_*`), segment/section structs, and dyld bind opcode definitions (`BIND_OPCODE_*`, `BIND_TYPE_*`).

