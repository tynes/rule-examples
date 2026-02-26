#!/usr/bin/env bash
set -euo pipefail

# fetch-transactions.sh — query compliance events and print a table
#
# Required env vars:
#   ETH_RPC_URL        — RPC endpoint
#   COMPLIANCE_ADDRESS — address of the Compliance contract
#
# Optional env vars:
#   FROM_BLOCK — starting block (default: 0)
#   TO_BLOCK   — ending block (default: latest)
#
# Usage:
#   fetch-transactions.sh [pending|rejected|approved|refunded|all]

FROM_BLOCK="${FROM_BLOCK:-0}"
TO_BLOCK="${TO_BLOCK:-latest}"

# Event topic0 signatures
TOPIC_PENDING=$(cast sig-event "Pending(bytes32,address,address,uint256,uint256,uint64,uint256,bytes)")
TOPIC_REJECTED=$(cast sig-event "Rejected(bytes32,address,address,uint256,uint256,uint64,uint256,bytes)")
TOPIC_APPROVED=$(cast sig-event "Approved(bytes32)")
TOPIC_REFUNDED=$(cast sig-event "Refunded(bytes32)")

require_env() {
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            echo "Error: $var is not set" >&2
            exit 1
        fi
    done
}

# Fetch rich events (Pending / Rejected) and output table rows.
# Args: $1 = topic0, $2 = status label
fetch_rich_events() {
    local topic0="$1"
    local status="$2"

    local logs
    logs=$(cast logs --json \
        --from-block "$FROM_BLOCK" \
        --to-block "$TO_BLOCK" \
        --address "$COMPLIANCE_ADDRESS" \
        "$topic0" 2>/dev/null) || return 0

    echo "$logs" | jq -r --arg status "$status" '
        .[] |
        .topics as $t |
        .data as $d |
        .blockNumber as $block |
        # indexed: id, from, to
        ($t[1]) as $id |
        ("0x" + ($t[2] | ltrimstr("0x"))[-40:]) as $from |
        ("0x" + ($t[3] | ltrimstr("0x"))[-40:]) as $to |
        # ABI-encoded data: value (32 bytes), mint (32), gasLimit (32), nonce (32), offset (32), length (32), bytes...
        ($d | ltrimstr("0x")) as $hex |
        ("0x" + $hex[0:64]) as $value_hex |
        ("0x" + $hex[128:192]) as $gas_hex |
        ("0x" + $hex[192:256]) as $nonce_hex |
        ($block | ltrimstr("0x")) as $block_clean |
        [$id, $from, $to, $value_hex, $gas_hex, $nonce_hex, $block, $status]
    ' 2>/dev/null | while IFS= read -r line; do
        # Parse the JSON array
        id=$(echo "$line" | jq -r '.[0]')
        from=$(echo "$line" | jq -r '.[1]')
        to=$(echo "$line" | jq -r '.[2]')
        value_hex=$(echo "$line" | jq -r '.[3]')
        gas_hex=$(echo "$line" | jq -r '.[4]')
        nonce_hex=$(echo "$line" | jq -r '.[5]')
        block_hex=$(echo "$line" | jq -r '.[6]')
        status_label=$(echo "$line" | jq -r '.[7]')

        value_wei=$(cast to-dec "$value_hex" 2>/dev/null || echo "0")
        value_eth=$(cast from-wei "$value_wei" 2>/dev/null || echo "0")
        gas=$(cast to-dec "$gas_hex" 2>/dev/null || echo "0")
        nonce=$(cast to-dec "$nonce_hex" 2>/dev/null || echo "0")
        block=$(cast to-dec "$block_hex" 2>/dev/null || echo "0")

        echo "$id $from $to ${value_eth} $gas $nonce $block $status_label"
    done
}

# Fetch simple events (Approved / Refunded) and output table rows.
# Args: $1 = topic0, $2 = status label
fetch_simple_events() {
    local topic0="$1"
    local status="$2"

    local logs
    logs=$(cast logs --json \
        --from-block "$FROM_BLOCK" \
        --to-block "$TO_BLOCK" \
        --address "$COMPLIANCE_ADDRESS" \
        "$topic0" 2>/dev/null) || return 0

    echo "$logs" | jq -r --arg status "$status" '
        .[] |
        .topics[1] as $id |
        .blockNumber as $block |
        [$id, $block, $status]
    ' 2>/dev/null | while IFS= read -r line; do
        id=$(echo "$line" | jq -r '.[0]')
        block_hex=$(echo "$line" | jq -r '.[1]')
        status_label=$(echo "$line" | jq -r '.[2]')

        block=$(cast to-dec "$block_hex" 2>/dev/null || echo "0")

        echo "$id $block $status_label"
    done
}

print_rich_table() {
    {
        echo "ID FROM TO VALUE_ETH GAS_LIMIT NONCE BLOCK STATUS"
        cat
    } | column -t
}

print_simple_table() {
    {
        echo "ID BLOCK STATUS"
        cat
    } | column -t
}

print_all_table() {
    {
        echo "ID BLOCK STATUS"
        cat
    } | sort -k2 -n | column -t
}

require_env ETH_RPC_URL COMPLIANCE_ADDRESS

filter="${1:-all}"

case "$filter" in
    pending)
        fetch_rich_events "$TOPIC_PENDING" "Pending" | print_rich_table
        ;;
    rejected)
        fetch_rich_events "$TOPIC_REJECTED" "Rejected" | print_rich_table
        ;;
    approved)
        fetch_simple_events "$TOPIC_APPROVED" "Approved" | print_simple_table
        ;;
    refunded)
        fetch_simple_events "$TOPIC_REFUNDED" "Refunded" | print_simple_table
        ;;
    all)
        {
            fetch_rich_events "$TOPIC_PENDING" "Pending" | awk '{print $1, $7, $8}'
            fetch_rich_events "$TOPIC_REJECTED" "Rejected" | awk '{print $1, $7, $8}'
            fetch_simple_events "$TOPIC_APPROVED" "Approved"
            fetch_simple_events "$TOPIC_REFUNDED" "Refunded"
        } | print_all_table
        ;;
    *)
        echo "Usage: $0 [pending|rejected|approved|refunded|all]" >&2
        exit 1
        ;;
esac
