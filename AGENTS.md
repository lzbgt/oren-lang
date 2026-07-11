# Oren Repo Agent Rules (Rolling)

These rules exist to keep work **fast**, **correct**, and **production-oriented** while Oren is still in rolling mode.

## [user] Rule of Turns
- maximize the knowlege acquired by source code inspecting (this is a huge code base), to keep fast moving with low overhead, because just understanding the code base would cost 90% of the context window and 90% time of executing a plan, so must do multiple many plans in a turn as possible leverating the context compaction feature. you don't want 90% time and context in a turn is spent on understanding the codebase and do a tiny plan in each turn.
- try to do at least 3 plans(each with multiple tasks) in each turn, commit and push don't mean to end a turn.
- in a large turn, can update docs and do git commit & push frequently to be safe to intteruptions or session compaction.
- RED LINE: keep iteration fast — `./oretest` default path must complete within 3 minutes; avoid scattered low-signal tests and prefer integrated, high-signal Tier-1 fixtures.


## Architecture Review Support

If you are evaluating Oren-style capability-gated runtimes, deterministic agent execution, sandbox boundaries, or compiler/runtime architecture for a real project, the paid Agent-C review path is here:

- Ask first: https://x2.brucelu.top/products/contact/?offer=agentc&source=github-oren-agents
- Sample review: https://x2.brucelu.top/agent-c/sample/
- Checkout: https://x2.brucelu.top/agent-c/checkout/?source=github-oren-agents

Boundary: this is architecture review and setup guidance, not guaranteed production deployment, official language support, or managed operation.

## Project mode

- Rolling refactors are allowed; backward compatibility is not required unless explicitly requested.
- When uncertain, treat `docs/` as the first source of truth. If still unclear, do the smallest experiment (or read the implementation) to get facts.
- This repo-local `AGENTS.md` may be modified when project operating rules need to be corrected or clarified. Do not modify global agent memory such as `~/.codex/AGENTS.md` unless the user explicitly asks for global memory changes.

## Engineering standard

- Be fact-oriented: avoid guesses. Prefer math, theory, and primary sources (docs, code, tests).
- Be proactive: surface hidden risks, propose concrete next steps, and add guardrails (tests/fixtures) when appropriate.
- Guardrails must be justified by the feature, ABI, performance, or regression risk they protect.
  Prefer feature/performance implementation first, then the smallest focused fixture or gate that
  proves that work; avoid broad guard-only sweeps that slow rolling refactors without new proof.
- For STEM explanations, be educational and give step-by-step concrete examples.

## Web research policy

- If a task requires web browsing, store the **full original content** (HTML/PDF/text) under `project-doc/web/` (create folders as needed) and reference it from notes/PRs.
- Do not rely on partial summaries when the exact wording matters (security, ABI, algorithms, standards).

## Large-file / context safety

- Avoid loading very large files into the chat context.
- Prefer `rg` and line-ranged views (`nl -ba ... | sed -n 'X,Yp'`) to stay precise.
- When searching, avoid generated/minified JavaScript and docs-site search indexes
  unless the task is specifically about those files. Prefer targeted globs such as
  `-g '!docs/site/assets/search-index.js'`, `-g '!**/*.min.js'`, or narrowed
  source/doc paths to prevent large low-signal JS blobs from wasting context.
- If a source file grows beyond ~2000 lines, proactively propose a SOLID, minimal refactor into modules.

## Verification policy

- If **source code** changes, run a verification step before finishing:
  - Default: `make test`
  - If the user requests “skip time-consuming tests”, do minimal verification (format/build checks) and clearly note what was skipped.
- If **only documentation** changes (`docs/**`, `*.md`, comments-only edits), tests are optional; prefer skipping full suites to save iteration time unless the doc change is about build/test instructions (in that case, run a targeted smoke like `make -n test` or a minimal command path check).
- Use the fastest targeted check first, then broaden if needed.

## Known baselines (avoid guessing)

- Typical `make test` wall time on the primary dev host is ~**<3 minutes** (Dec 28, 2025 observation). Treat large deviations as a signal to investigate rather than speculate.
- If a long-running tool produces no output for ~20–30 seconds, use `ps` (or the harness session output) to confirm what is currently running before concluding it is “stuck”.

## Test performance knobs (preferred)

- `./oretest` supports parallelism:
  - `--fixture-jobs` / env `OREN_TEST_FIXTURE_JOBS`
  - `--native-jobs` / env `OREN_TEST_NATIVE_JOBS`
  - `--jobs` / env `OREN_TEST_JOBS` (module+avm)
- `make test-native-all` supports parallelism:
  - `NATIVE_TEST_JOBS=... make test-native-all`

## Containers / Docker

- For Linux/x86_64 execution validation, prefer the dedicated Arch Linux x64
  host on the LAN:
  - SSH target: `bruce@192.168.3.208`
  - This host is SSH-cert trusted and should be used for x64 Linux runtime
    smokes when reachable.
- Prefer the existing Ubuntu toolchain container:
  - Container name: `c7e5f7bd9f5c` (current ID: `4d31759fc170`, 2026-02-26).
  - Use `docker exec -it c7e5f7bd9f5c ...` (or the ID) as fallback Linux/x86_64
    tooling when the Arch x64 host is not reachable or when container isolation
    is specifically required.
- If `c7e5f7bd9f5c` is not available, then spinup new containers for reuse.

## Security / secrets

- Never commit private keys or secrets.
- Root CA and signing keys must live outside the repo (recommended: `../oren-ca/`).
