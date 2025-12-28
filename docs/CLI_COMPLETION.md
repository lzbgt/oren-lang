# CLI Completion (bash / zsh)

Oren ships a built-in completion generator:

- `oren completion bash`
- `oren completion zsh`

The generated scripts are intentionally minimal and deterministic:

- Completes subcommands (`build`, `meta`, `dump`, …)
- Completes option *names* (e.g. `--backend`, `--target`)
- Completes a small set of enum-like option *values*:
  - `--backend={c|native|bytecode}`
  - `--target={macos|linux|windows}` (rolling)
  - `--arch={arm64|x64}` (rolling)
  - `--stdlib-mode={source|obc}`
  - `--help=json` / `-h=json`
- Completes `oren dump <kind>` where `<kind>` is one of `tokens|linked|graph`
- Does basic file completion for common positionals (e.g. `oren build <file>`, `oren meta <file>`, `oren dump <kind> <file>`, `oren scan <lib>`)

It does **not** currently validate combinations or suggest paths with type filters (e.g. only `*.oren`).

## Bash

One-shot for the current shell session:

```bash
source <(oren completion bash)
```

To enable permanently, add to `~/.bashrc`:

```bash
source <(oren completion bash)
```

## Zsh

One-shot for the current shell session:

```zsh
source <(oren completion zsh)
```

To enable permanently, add to `~/.zshrc`:

```zsh
source <(oren completion zsh)
```

## Notes

- Because the completion scripts are generated from the compiler’s current CLI spec, upgrading Oren automatically upgrades completion.
- If you package Oren as a release artifact, you can also ship the completion scripts by capturing them at build time:
  - `oren completion bash > oren.bash`
  - `oren completion zsh > _oren`
