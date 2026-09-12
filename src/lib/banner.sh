#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Library: Banner & Branding
# Part of Phase 4 Distribution Architecture
# ==============================================================================

print_banner() {
    cat << "EOF"
  _   _ _____ _   _ ____   ___  _   _ _____  __
 | \ | | ____| | | |  _ \ / _ \| \ | |_ _\ \/ /
 |  \| |  _| | | | | |_) | | | |  \| || | \  / 
 | |\  | |___| |_| |  _ <| |_| | |\  || | /  \ 
 |_| \_|_____|\___/|_| \_\\___/|_| \_|___/_/\_\
EOF
    echo -e "  ${BOLD}NEURONIX${RESET} - ${DIM}Deterministic AI-Augmented Substrate${RESET}  ${CYAN}v${VERSION}${RESET}\n"
}
