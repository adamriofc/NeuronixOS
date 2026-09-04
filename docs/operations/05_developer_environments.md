# NEURONIX OS Runbook: Ephemeral Developer Environments

## 1. Ephemeral Subshell Model

NEURONIX developer environments (`neuronix dev <stack>`) provision hermetic toolchains inside isolated subshells without polluting global system paths or mutating `/etc/nixos`. When the shell terminates, memory allocations are purged and no residual global packages remain.

## 2. Supported Curated Stacks

- `python`: Python 3, uv, ruff, pyright, postgresql.
- `rust`: rustc, cargo, rust-analyzer, clippy.
- `node`: nodejs 20, pnpm, typescript, eslint.
- `ai`: Python 3, PyTorch, ollama, jupyterlab, pandas.
- `go`: Go, gopls, golangci-lint, delve.
- `web3`: rustc, cargo, nodejs 20, solana-cli.

## 3. Usage Patterns

### Launching an Interactive Environment
```bash
neuronix dev rust
```

### Inspecting Stack Toolchain Manifests
Query toolchain packages and channels in JSON format without launching a shell:

```bash
neuronix dev python --manifest
```

### One-Off Ad-Hoc Package Execution
Test arbitrary CLI utilities without installing them permanently:

```bash
neuronix run jq ripgrep htop
```
