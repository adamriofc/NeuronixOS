#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Mutation Testing & Fault Injection Resilience Harness
# Systematically injects deliberate faults and mutations to verify
# that security gates, validators, and contract harnesses catch regressions.
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0
FAILED=0

# Colors
if [[ -t 1 ]]; then
    GREEN="\033[32m"
    RED="\033[31m"
    CYAN="\033[36m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    GREEN=""
    RED=""
    CYAN=""
    BOLD=""
    RESET=""
fi

echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║     NEURONIX OS FAULT INJECTION & MUTATION RESILIENCE HARNESS     ║${RESET}"
echo -e "${BOLD}${CYAN}║    Injecting Deliberate Mutations to Verify Defensive Triggers    ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

mutation_assert() {
    local desc="$1"
    local condition="$2"

    echo -ne "  [MUTATION] ${desc} ... "
    if eval "$condition"; then
        echo -e "${GREEN}KILLED (PASS)${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}SURVIVED (FAIL)${RESET}"
        ((FAILED++))
    fi
}

CLI_BIN="${PROJECT_ROOT}/src/neuronix"
INSTALLER_BIN="${PROJECT_ROOT}/installer/scripts/neuronix-install-engine.sh"

# Mutation 1: Inject invalid package name into verify
mutation_assert "Mutation M1: Malformed package name with shell payload" \
    "! bash '${CLI_BIN}' verify 'foo; echo pwned' >/dev/null 2>&1"

# Mutation 2: Inject invalid desktop environment into installer
mutation_assert "Mutation M2: Unsupported desktop environment flag" \
    "! SELECTED_DESKTOP='invalid_wm' bash '${INSTALLER_BIN}' >/dev/null 2>&1"

# Mutation 3: Inject invalid username with path traversal
mutation_assert "Mutation M3: Path traversal username injection" \
    "! TARGET_USER='../../bin/sh' bash '${INSTALLER_BIN}' >/dev/null 2>&1"

# Mutation 4: Inject invalid hostname with RFC 1123 violations
mutation_assert "Mutation M4: Hostname containing illegal underscores or symbols" \
    "! TARGET_HOSTNAME='bad_host_name!' bash '${INSTALLER_BIN}' >/dev/null 2>&1"

# Mutation 5: Inject unauthorized command into run_privileged allowlist
test_unauthorized_priv() {
    (
        source "${CLI_BIN}"
        run_privileged "cat /etc/shadow" >/dev/null 2>&1
    )
}
mutation_assert "Mutation M5: Unauthorized command execution via run_privileged" \
    "! test_unauthorized_priv"

# Mutation 6: Inject missing telemetry marker into shadow VM verification
test_missing_marker() {
    local tmp_runner
    tmp_runner=$(mktemp)
    cat << 'EOF' > "$tmp_runner"
#!/usr/bin/env bash
echo "kernel ok"
# Missing systemd and 9p and guest ready markers
exit 0
EOF
    chmod +x "$tmp_runner"
    local res=0
    NEURONIX_TEST_VM_RUNNER="$tmp_runner" bash "${PROJECT_ROOT}/src/shadow_vm.sh" --smoke-test >/dev/null 2>&1 || res=$?
    rm -f "$tmp_runner"
    [[ $res -ne 0 ]]
}
mutation_assert "Mutation M6: Incomplete guest telemetry in Shadow VM runner" \
    "test_missing_marker"

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Fault Mutations Injected : $((PASSED + FAILED))"
echo -e "  Mutations Successfully Killed  : ${PASSED}"
echo -e "  Mutations Survived (Regressed) : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ 100% MUTATION RESILIENCE SCORE ACHIEVED (ZERO MUTANTS SURVIVED)${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ MUTATION TESTING DETECTED DEFENSIVE VULNERABILITIES${RESET}\n"
    exit 1
fi
