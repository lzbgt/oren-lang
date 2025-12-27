# CLI Completion (bash / zsh)

Oren ships a built-in completion generator:

- `oren completion bash`
- `oren completion zsh`

The generated scripts are intentionally minimal and deterministic:

- Completes subcommands (`build`, `meta`, `dump`, …)
- Completes option *names* (e.g. `--backend`, `--target`)
- Completes a small set of enum-like option *values*:
  - `--backend={c|native|bytecode}`
  - `--target={macos|linux}`
  - `--arch={arm64}` (rolling; currently the only supported value)
  - `--stdlib-mode={source|obc}`
  - `--help=json` / `-h=json`

It does **not** currently do path completion (files, directories) or validate combinations.

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
