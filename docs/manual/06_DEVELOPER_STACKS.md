# Chapter 6: Hermetic Developer Environments

## 1. Declarative Ephemeral Toolchains

Traditional Linux distributions require installing compiler toolchains, package managers, and language runtimes globally into `/usr/bin`. This results in version conflicts, broken system libraries, and cluttered root partitions.

NEURONIX OS provides instant, isolated developer stacks via `neuronix dev <stack>`. Toolchains are fetched directly from `/nix/store` into a transient subshell in RAM. When the subshell is closed, no residual files remain.

---

## 2. Curated Stack Catalog

| Stack Identifier | Bundled Packages & Tooling | Primary Use Cases |
| :--- | :--- | :--- |
| `python` | `python3`, `uv`, `ruff`, `pyright`, `postgresql` | Modern backend development, rapid scripting, API services. |
| `rust` | `rustc`, `cargo`, `rust-analyzer`, `clippy` | Systems programming, low-level utilities, performance engines. |
| `node` | `nodejs_20`, `pnpm`, `typescript`, `eslint` | Fullstack web applications, TypeScript microservices, frontend apps. |
| `ai` | `python3`, `pytorch`, `ollama`, `jupyterlab`, `pandas` | Local LLM inference, PyTorch model training, data analysis. |
| `go` | `go`, `gopls`, `golangci-lint`, `delve` | Cloud-native microservices, container tooling, high-throughput APIs. |
| `web3` | `rustc`, `cargo`, `nodejs_20`, `solana-cli` | Smart contract development, decentralized protocol engineering. |

---

## 3. Usage & Declarative Manifest Synthesis

### Interactive Execution:
```bash
# Launch interactive Python environment
neuronix dev python

# Launch interactive AI & PyTorch environment
neuronix dev ai
```

### Non-Interactive Manifest Export (CI/CD & AI Agent Inspection):
To inspect a stack's package closure without spawning an interactive terminal subshell:

```bash
neuronix dev python --manifest
```

Output:
```json
{
  "stack": "python",
  "channel": "nixos-26.05",
  "hermetic": true,
  "ephemeral": true,
  "packages": ["python3", "uv", "ruff", "pyright", "postgresql"]
}
```
