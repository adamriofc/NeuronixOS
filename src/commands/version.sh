#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_version() {
    print_banner
    echo -e "Version       : ${CYAN}${VERSION}${RESET}"
    echo -e "License       : Apache License 2.0"
    echo -e "Substrate     : NixOS / Pure-Functional Linux"
    echo -e "Engine Target : Linux x86_64, aarch64, Darwin, WSL2"
    echo -e "Repository    : https://github.com/adamriofc/NeuronixOS"
}

# Main CLI Dispatcher
