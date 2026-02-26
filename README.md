# rule-examples

Example `IRule` implementations for the cross-chain compliance screening system. These contracts plug into a `Compliance` contract that screens deposits and withdrawals on OP Stack bridges.

## Contracts

### StaticAnalysisRule

Evaluates transactions against owner-configurable deny lists across three dimensions (sender, target, function selector) with two severity levels:

- **Flagged** — returns `Pending` for manual review
- **Rejected** — returns `Rejected` immediately

### RateLimitRule

Enforces a leaky-bucket rate limit on ETH value. When projected usage exceeds the configured limit, the transaction is flagged as `Pending` (not `Rejected`) so it can be re-evaluated later via `settle()` once the bucket has drained.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) — `forge`, `cast`
- [just](https://github.com/casey/just#installation) — command runner

## Quick Start

```bash
# Build
just build

# Run tests
just test

# Format
just fmt
```

## Deployment

Copy `.env.example` or create a `.env` file:

```bash
ETH_RPC_URL=https://...
PRIVATE_KEY=0x...
COMPLIANCE_ADDRESS=0x...
```

Deploy contracts:

```bash
# StaticAnalysisRule — pass the owner address
just deploy-static-analysis 0xYourOwnerAddress

# RateLimitRule — pass owner, limit (wei), and window (seconds)
just deploy-rate-limit 0xYourOwnerAddress 10000000000000000000 3600
```

## Operations

All operations are available as `just` recipes. Run `just --list` to see them all.

### Rule Management

```bash
just add-rule 0xRuleAddress        # Register a rule with the Compliance contract
just remove-rule 0xRuleAddress     # Remove a rule
just list-rules                    # List all registered rules
```

### Transaction Management

```bash
just approve 0xTransactionId       # Approve a pending transaction
just reject 0xTransactionId        # Reject a pending transaction
just status 0xTransactionId        # Check transaction status
```

### Querying Events

```bash
just pending                       # Show pending transactions
just rejected                      # Show rejected transactions
just approved                      # Show approved transactions
just refunded                      # Show refunded transactions
just transactions                  # Show all transactions
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `ETH_RPC_URL` | Yes | RPC endpoint URL |
| `PRIVATE_KEY` | Write ops | Private key for signing transactions |
| `COMPLIANCE_ADDRESS` | Ops scripts | Address of the deployed Compliance contract |
| `OWNER` | Deploy | Owner address for new rule contracts |
| `LIMIT` | Deploy (RateLimitRule) | Maximum wei allowed within the rate limit window |
| `WINDOW` | Deploy (RateLimitRule) | Drain period in seconds |
| `FROM_BLOCK` | No | Starting block for event queries (default: `0`) |
| `TO_BLOCK` | No | Ending block for event queries (default: `latest`) |
