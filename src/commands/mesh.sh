#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_mesh() {
    local json_output=0
    local sub=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${PROGRAM_NAME} mesh [status|peers] [OPTIONS]\n"
                echo -e "  Discovers and queries local P2P binary cache peers via mDNS/Avahi.\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${CYAN}--json${RESET}     Output status in structured JSON"
                echo -e "  ${CYAN}-h, --help${RESET} Show this help"
                return 0
                ;;
            status|peers|discover|share)
                sub="$1"
                shift
                ;;
            *)
                sub="$1"
                shift
                ;;
        esac

    done
    sub="${sub:-status}"

    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.mesh import get_mesh_status

json_out = sys.argv[1] == '1'
st = get_mesh_status()
if json_out:
    print(json.dumps(st, indent=2))
    sys.exit(0)

print('\033[1m================================================================\033[0m')
print('  \033[1mNEURONIX P2P LOCAL BINARY MESH (mDNS)\033[0m')
print('\033[1m================================================================\033[0m')
mesh_st = '\033[38;5;82mACTIVE\033[0m' if st['status'] == 'active' else '\033[38;5;220mSTANDBY\033[0m'
cache_st = '\033[38;5;82mActive (nix-serve listening)\033[0m' if st.get('cache_serving') else '\033[38;5;220mStandby\033[0m'
mdns_st = '\033[38;5;82mEnabled\033[0m' if st['mdns_daemon_active'] else '\033[38;5;196mInactive\033[0m'
print(f'  Mesh Status     : {mesh_st}')
print(f'  Local Node      : {st[\"local_node\"][\"hostname\"]} ({st[\"local_node\"][\"local_ip\"]})')
print(f'  Cache Port      : TCP {st[\"local_node\"][\"mesh_port\"]}')
print(f'  Cache Serving   : {cache_st}')
print(f'  mDNS Broadcaster: {mdns_st}')
print('----------------------------------------------------------------')
peers = st.get('peers', [])
v_count = st.get('verified_peer_count', 0)
print(f'  Discovered LAN Peers: {len(peers)} ({v_count} verified)')
if peers:
    for p in peers:
        ver_badge = '\033[38;5;82m[VERIFIED]\033[0m' if p.get('cache_verified') else '\033[38;5;220m[UNVERIFIED]\033[0m'
        print(f'  ● {p[\"name\"]} @ {p[\"ip\"]}:{p[\"port\"]} {ver_badge}')
else:
    print('    \033[2m(No nearby NEURONIX nodes broadcasting on local subnet)\033[0m')
print('\033[1m================================================================\033[0m')
" "$json_output"
}

