# Contributing to NEURONIX OS

Thank you for your interest in contributing to NEURONIX OS. We welcome contributions across distribution modules, hardware profiles, installer logic, documentation, and tooling.

## Development Environment

To start working on the repository, enter the hermetic development shell using Nix Flakes:

```bash
git clone https://github.com/adamriofc/neuronix.git
cd neuronix
nix develop
```

This provisions the development toolchain, including QEMU, Calamares testing dependencies, btrfs-progs, and code formatters.

## Code Standards

### Nix Modules
- Use standard Nix formatting.
- Modules must expose modular `enable` flags under `services.*` or `hardware.*` where appropriate.
- Avoid impure system paths or hardcoded machine identifiers.
- Validate syntax before submitting:
  ```bash
  nix-instantiate --parse flake.nix
  nix-instantiate --parse modules/**/*.nix
  ```

### Shell Scripts
- Write scripts targeting standard POSIX or bash with strict error handling:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  ```
- Do not introduce external dependencies without checking command availability.
- Ensure scripts run cleanly in both root and unprivileged user environments.

## Testing & Quality Gates

NEURONIX maintains an automated test suite comprising 851 assertions. All tests must pass with a 100% success rate before pull requests can be merged.

Run the test suite locally:

```bash
# Run the master test runner (596 tests across 23 suites)
bash tests/run_all_tests.sh

# Run the distribution standalone harness (209 tests)
bash tests/test_distro_suite.sh

# Run the core functional harness (14 tests)
bash tests/test_neuronix_core.sh

# Run the end-to-end release lifecycle gate (32 tests)
bash tests/test_release_lifecycle.sh
```

## Commit Conventions

We follow Conventional Commits for commit messages:
- `feat(scope): ...` for new features or hardware modules.
- `fix(scope): ...` for bug fixes.
- `docs(scope): ...` for documentation updates.
- `test(scope): ...` for adding or refining test assertions.
- `refactor(scope): ...` for structural code improvements without behavioral changes.

## Pull Request Process

1. Fork the repository and create your feature branch:
   ```bash
   git checkout -b feat/my-hardware-profile
   ```
2. Commit your changes adhering to the commit conventions.
3. Run all 851 automated tests and ensure zero failures.
4. Push to your fork and submit a Pull Request targeting `main`.
5. Ensure GitHub Actions CI checks complete successfully.
