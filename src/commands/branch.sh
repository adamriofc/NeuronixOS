#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_branch() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        create)
            local src="${1:-.}"
            local name="${2:-experiment}"
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"
            PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.storage import create_workspace_branch
try:
    res = create_workspace_branch(sys.argv[1], sys.argv[2])
    print(json.dumps(res, indent=2))
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'error': str(e)}))
    sys.exit(1)
" "$src" "$name"
            ;;
        list)
            local src="${1:-.}"
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"
            PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.storage import list_workspace_branches
branches = list_workspace_branches(sys.argv[1])
print(json.dumps({'workspace': sys.argv[1], 'branches': branches}, indent=2))
" "$src"
            ;;
        revert)
            local src="${1:-.}"
            local name="${2:-experiment}"
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"
            PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.storage import revert_workspace_branch
try:
    res = revert_workspace_branch(sys.argv[1], sys.argv[2])
    print(json.dumps(res, indent=2))
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'error': str(e)}))
    sys.exit(1)
" "$src" "$name"
            ;;
        *)
            echo -e "${BOLD}USAGE:${RESET}"
            echo -e "  ${PROGRAM_NAME} branch [create|list|revert] <path> [branch_name]\n"
            echo -e "  Point-in-time CoW snapshot and reflink workspace branching.\n"
            return 0
            ;;
    esac
}

