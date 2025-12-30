# Oren Repo Agent Rules (Rolling)

These rules exist to keep work **fast**, **correct**, and **production-oriented** while Oren is still in rolling mode.

## Project mode

- Rolling refactors are allowed; backward compatibility is not required unless explicitly requested.
- When uncertain, treat `docs/` as the first source of truth. If still unclear, do the smallest experiment (or read the implementation) to get facts.

## Engineering standard

- Be fact-oriented: avoid guesses. Prefer math, theory, and primary sources (docs, code, tests).
- Be proactive: surface hidden risks, propose concrete next steps, and add guardrails (tests/fixtures) when appropriate.
- For STEM explanations, be educational and give step-by-step concrete examples.

## Web research policy

- If a task requires web browsing, store the **full original content** (HTML/PDF/text) under `project-doc/web/` (create folders as needed) and reference it from notes/PRs.
- Do not rely on partial summaries when the exact wording matters (security, ABI, algorithms, standards).

## Large-file / context safety

- Avoid loading very large files into the chat context.
- Prefer `rg` and line-ranged views (`nl -ba ... | sed -n 'X,Yp'`) to stay precise.
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

- Do **not** start new containers (no `docker run`, no `docker compose up`).
- Always use the already-running Ubuntu toolchain container:
  - Container ID: `c7e5f7bd9f5c`
  - Use `docker exec -it c7e5f7bd9f5c ...` for all Linux/x86_64 validation and tooling.
  - If the container is not running, stop and ask the user to restore it (do not create a replacement).

## Security / secrets

- Never commit private keys or secrets.
- Root CA and signing keys must live outside the repo (recommended: `../oren-ca/`).
