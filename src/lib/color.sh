#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Library: Color Palettes & Logging Formatters
# Part of Phase 4 Distribution Architecture
# ==============================================================================

if [[ -t 1 ]]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    GREEN="\033[38;5;82m"
    CYAN="\033[38;5;51m"
    BLUE="\033[38;5;39m"
    YELLOW="\033[38;5;220m"
    RED="\033[38;5;196m"
    MAGENTA="\033[38;5;207m"
    GRAY="\033[38;5;245m"
    RESET="\033[0m"
else
    BOLD=""
    DIM=""
    GREEN=""
    CYAN=""
    BLUE=""
    YELLOW=""
    RED=""
    MAGENTA=""
    GRAY=""
    RESET=""
fi

log_info()    { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
log_success() { echo -e "  ${GREEN}✔${RESET}  $*"; }
log_warn()    { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_error()   { echo -e "  ${RED}✖${RESET}  $*" >&2; }
log_step()    { echo -e "  ${CYAN}➔${RESET}  ${BOLD}$*${RESET}"; }
