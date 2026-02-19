## Agent Task Tracker (Concise)

Project-wide roadmap / rolling tasks live in `docs/TODOS.md`. This file stays intentionally short and only tracks immediate, actionable agent follow-ups.

- P2/S: Add `ConnectTimeout` (ssh/scp) safeguards in `scripts/verify_native_matrix.sh` to reduce hang risk on flaky networks.
- P2/S: Consider allowing non-macOS hosts for partial targets (e.g. `--targets local` on Linux) if that becomes a real workflow.
- P1/M: Implement AVM unboxed list<int> payload + opcode lowering (see `docs/DESIGN_COLLECTIONS.md` §4B) to close OBC list<int> gaps.
