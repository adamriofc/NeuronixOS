#!/usr/bin/env bash
# ==============================================================================
# Suite 18: Distro One-Command Dev Stacks & Negative Fuzzing Matrix (35 Tests)
# Exhaustively stress-tests 'neuronix dev' parameter bounds and toolchain proofs
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT}/bin/neuronix"

start_suite "18 - Distro Dev Stacks & Boundary Fuzzing Matrix"

# 1-6. Toolchain Content Proving in Dry-Run
OUT_PY=$(DEV_DRY_RUN=1 "$TARGET_BIN" dev python)
assert_output_contains "echo '$OUT_PY'" "uv" "Python toolchain includes uv"
assert_output_contains "echo '$OUT_PY'" "ruff" "Python toolchain includes ruff"
assert_output_contains "echo '$OUT_PY'" "pyright" "Python toolchain includes pyright"

OUT_RS=$(DEV_DRY_RUN=1 "$TARGET_BIN" dev rust)
assert_output_contains "echo '$OUT_RS'" "rust-analyzer" "Rust toolchain includes rust-analyzer"
assert_output_contains "echo '$OUT_RS'" "clippy" "Rust toolchain includes clippy"

OUT_JS=$(DEV_DRY_RUN=1 "$TARGET_BIN" dev node)
assert_output_contains "echo '$OUT_JS'" "nodePackages.pnpm" "Node toolchain includes pnpm"
assert_output_contains "echo '$OUT_JS'" "nodePackages.typescript" "Node toolchain includes typescript"

OUT_AI=$(DEV_DRY_RUN=1 "$TARGET_BIN" dev ai)
assert_output_contains "echo '$OUT_AI'" "pytorch" "AI toolchain includes pytorch"
assert_output_contains "echo '$OUT_AI'" "ollama" "AI toolchain includes ollama"
assert_output_contains "echo '$OUT_AI'" "jupyterlab" "AI toolchain includes jupyterlab"

OUT_GO=$(DEV_DRY_RUN=1 "$TARGET_BIN" dev go)
assert_output_contains "echo '$OUT_GO'" "gopls" "Go toolchain includes gopls"
assert_output_contains "echo '$OUT_GO'" "delve" "Go toolchain includes delve"

OUT_W3=$(DEV_DRY_RUN=1 "$TARGET_BIN" dev web3)
assert_output_contains "echo '$OUT_W3'" "solana-cli" "Web3 toolchain includes solana-cli"

# 14-23. Rejection of Unsupported / Arbitrary Language Stacks
assert_exit_code "$TARGET_BIN dev perl 2>/dev/null" 1 "Perl stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev scala 2>/dev/null" 1 "Scala stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev kotlin 2>/dev/null" 1 "Kotlin stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev haskell 2>/dev/null" 1 "Haskell stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev elixir 2>/dev/null" 1 "Elixir stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev clojure 2>/dev/null" 1 "Clojure stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev fortran 2>/dev/null" 1 "Fortran stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev cobol 2>/dev/null" 1 "Cobol stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev r 2>/dev/null" 1 "R stack is rejected with exit 1"
assert_exit_code "$TARGET_BIN dev swift 2>/dev/null" 1 "Swift stack is rejected with exit 1"

# 24-29. Shell Injection & Metacharacter Neutralization
assert_exit_code "$TARGET_BIN dev 'python; echo hacked' 2>/dev/null" 1 "Semicolon shell injection rejected"
assert_exit_code "$TARGET_BIN dev 'rust | cat' 2>/dev/null" 1 "Pipe shell injection rejected"
assert_exit_code "$TARGET_BIN dev 'node && ls' 2>/dev/null" 1 "Double ampersand injection rejected"
assert_exit_code "$TARGET_BIN dev '\$(whoami)' 2>/dev/null" 1 "Subshell command substitution rejected"
assert_exit_code "$TARGET_BIN dev 'ai > /tmp/test' 2>/dev/null" 1 "Redirection injection rejected"
assert_exit_code "$TARGET_BIN dev 'go\`whoami\`' 2>/dev/null" 1 "Backtick execution injection rejected"

# 30-35. Strict Case & Boundary Invariants
assert_exit_code "$TARGET_BIN dev PYTHON 2>/dev/null" 1 "Uppercase PYTHON is rejected for consistency"
assert_exit_code "$TARGET_BIN dev Rust 2>/dev/null" 1 "Mixed-case Rust is rejected for consistency"
assert_exit_code "$TARGET_BIN dev NODE 2>/dev/null" 1 "Uppercase NODE is rejected for consistency"
assert_exit_code "$TARGET_BIN dev AI 2>/dev/null" 1 "Uppercase AI is rejected for consistency"
assert_exit_code "$TARGET_BIN dev '' 2>/dev/null" 1 "Empty string argument is rejected"
assert_exit_code "$TARGET_BIN dev '   ' 2>/dev/null" 1 "Whitespace-only argument is rejected"
