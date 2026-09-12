## Description
<!-- Brief description of changes and the problem solved -->

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing functionality to change)
- [ ] Documentation update
- [ ] Hardware module / hardware profile
- [ ] Test enhancement or assurance qualification

## Testing & Verification
<!-- Describe the tests you executed to verify your changes -->
- [ ] `nix-instantiate --parse` passes for all modified `.nix` files
- [ ] `bash tests/run_all_tests.sh` (all master suites pass with 0 failures)
- [ ] `bash tests/test_distro_suite.sh` (all distro suites pass with 0 failures)
- [ ] Python test suites pass: `pytest` or `python3 -m unittest discover tests`
- [ ] Manual testing on target environment / hardware

## Checklist
- [ ] Code follows project conventions and strict fail-closed security invariants
- [ ] Self-review completed with no regressions introduced
- [ ] Zero unencrypted private keys, tokens, or credentials
- [ ] No hardcoded temporary file paths; all temporary workspaces use secure directories
- [ ] Version bumped in `version.nix` if applicable
- [ ] CHANGELOG.md updated if user-facing change
- [ ] Zero Unicode em-dashes introduced across all modified files
