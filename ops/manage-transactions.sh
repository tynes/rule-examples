#!/usr/bin/env bash
set -euo pipefail

# manage-transactions.sh — approve, reject, or check status of transactions
#
# Required env vars:
#   ETH_RPC_URL        — RPC endpoint
#   COMPLIANCE_ADDRESS — address of the Compliance contract
#   PRIVATE_KEY        — (write operations only) owner key
#
# Usage:
#   manage-transactions.sh approve <TX_ID>
#   manage-transactions.sh reject  <TX_ID>
#   manage-transactions.sh status  <TX_ID>

usage() {
    echo "Usage: $0 {approve|reject|status} <TX_ID>" >&2
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

decode_status() {
    case "$1" in
        0) echo "Approved" ;;
        1) echo "Pending" ;;
        2) echo "Rejected" ;;
        3) echo "Refunded" ;;
        *) echo "Unknown($1)" ;;
    esac
}

cmd="${1:-}"
tx_id="${2:-}"

[[ -z "$cmd" || -z "$tx_id" ]] && usage

case "$cmd" in
    approve)
        require_env ETH_RPC_URL COMPLIANCE_ADDRESS PRIVATE_KEY
        cast send "$COMPLIANCE_ADDRESS" "approve(bytes32)" "$tx_id" \
            --rpc-url "$ETH_RPC_URL" \
            --private-key "$PRIVATE_KEY"
        ;;
    reject)
        require_env ETH_RPC_URL COMPLIANCE_ADDRESS PRIVATE_KEY
        cast send "$COMPLIANCE_ADDRESS" "reject(bytes32)" "$tx_id" \
            --rpc-url "$ETH_RPC_URL" \
            --private-key "$PRIVATE_KEY"
        ;;
    status)
        require_env ETH_RPC_URL COMPLIANCE_ADDRESS
        result=$(cast call "$COMPLIANCE_ADDRESS" "status(bytes32)(bool,uint8)" "$tx_id" \
            --rpc-url "$ETH_RPC_URL")
        is_final=$(echo "$result" | sed -n '1p')
        status_num=$(echo "$result" | sed -n '2p')
        status_name=$(decode_status "$status_num")
        echo "Status: $status_name (isFinal: $is_final)"
        ;;
    *)
        usage
        ;;
esac
