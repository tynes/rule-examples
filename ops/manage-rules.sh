#!/usr/bin/env bash
set -euo pipefail

# manage-rules.sh — add, remove, or list compliance rules
#
# Required env vars:
#   ETH_RPC_URL        — RPC endpoint
#   COMPLIANCE_ADDRESS — address of the Compliance contract
#   PRIVATE_KEY        — (write operations only) deployer / owner key
#
# Usage:
#   manage-rules.sh add    <RULE_ADDRESS>
#   manage-rules.sh remove <RULE_ADDRESS>
#   manage-rules.sh list

usage() {
    echo "Usage: $0 {add|remove|list} [RULE_ADDRESS]" >&2
    exit 1
}

require_env() {
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            echo "Error: $var is not set" >&2
            exit 1
        fi
    done
}

cmd="${1:-}"
shift || true

case "$cmd" in
    add)
        [[ $# -lt 1 ]] && usage
        require_env ETH_RPC_URL COMPLIANCE_ADDRESS PRIVATE_KEY
        cast send "$COMPLIANCE_ADDRESS" "addRule(address)" "$1" \
            --rpc-url "$ETH_RPC_URL" \
            --private-key "$PRIVATE_KEY"
        ;;
    remove)
        [[ $# -lt 1 ]] && usage
        require_env ETH_RPC_URL COMPLIANCE_ADDRESS PRIVATE_KEY
        cast send "$COMPLIANCE_ADDRESS" "removeRule(address)" "$1" \
            --rpc-url "$ETH_RPC_URL" \
            --private-key "$PRIVATE_KEY"
        ;;
    list)
        require_env ETH_RPC_URL COMPLIANCE_ADDRESS
        cast call "$COMPLIANCE_ADDRESS" "rules()(address[])" \
            --rpc-url "$ETH_RPC_URL"
        ;;
    *)
        usage
        ;;
esac
