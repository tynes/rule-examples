# rule-examples

Example [`IRule`](interfaces/universal/IRule.sol) implementations for the cross-chain compliance screening system. These contracts plug into a [`Compliance`](interfaces/universal/ICompliance.sol) contract that screens deposits and withdrawals on OP Stack bridges.

## Table of Contents

- [Overview](#overview)
- [Contracts](#contracts)
  - [StaticAnalysisRule](#staticanalysisrule)
  - [RateLimitRule](#ratelimitrule)
- [Interfaces](#interfaces)
  - [IRule](#irule)
  - [ICompliance](#icompliance)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment](#deployment)
- [Operations](#operations)
  - [Rule Management](#rule-management)
  - [Transaction Management](#transaction-management)
  - [Querying Events](#querying-events)
- [Environment Variables](#environment-variables)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [Transaction Lifecycle](#transaction-lifecycle)
- [Writing Your Own Rule](#writing-your-own-rule)

## Overview

The `Compliance` contract sits in front of an OP Stack bridge and evaluates every cross-chain transaction against a set of pluggable rules. Each rule implements the `IRule` interface and returns one of four statuses:

| Status | Meaning |
|---|---|
| `Approved` | Transaction passes this rule |
| `Pending` | Transaction is held for manual review or later re-evaluation |
| `Rejected` | Transaction is denied |
| `Refunded` | ETH has been returned to the sender (terminal state) |

If **any** rule returns `Pending` or `Rejected`, the transaction does not proceed immediately. The owner can later approve or reject pending transactions, or anyone can call `settle()` to re-evaluate rules after conditions change (e.g., a rate-limit bucket drains).

This repository provides two example rule implementations with full test suites, deployment scripts, and operational tooling.

## Contracts

### StaticAnalysisRule

[`src/StaticAnalysisRule.sol`](src/StaticAnalysisRule.sol)

A deny-list based rule that evaluates transactions against owner-configurable lists across three dimensions and two severity levels.

**Dimensions:**
- **Senders** -- the `_from` address
- **Targets** -- the `_to` address
- **Function selectors** -- the first 4 bytes of `_data`

**Severity levels:**
- **Flagged** -- returns `Pending` (held for manual review)
- **Rejected** -- returns `Rejected` (denied immediately)

When an address or selector appears in both the flagged and rejected lists, **rejected takes priority**.

If calldata is shorter than 4 bytes, selector checks are skipped entirely.

**Owner functions:**

```solidity
setFlaggedSender(address _sender, bool _flagged)
setFlaggedTarget(address _target, bool _flagged)
setFlaggedSelector(bytes4 _selector, bool _flagged)
setRejectedSender(address _sender, bool _rejected)
setRejectedTarget(address _target, bool _rejected)
setRejectedSelector(bytes4 _selector, bool _rejected)
```

**Evaluation logic:**

```
1. If sender or target is in the rejected list → Rejected
2. If selector is in the rejected list         → Rejected
3. If sender or target is in the flagged list  → Pending
4. If selector is in the flagged list          → Pending
5. Otherwise                                   → Approved
```

This is a `view` function -- it does not modify state on evaluation.

### RateLimitRule

[`src/RateLimitRule.sol`](src/RateLimitRule.sol)

A leaky-bucket rate limiter that controls the total ETH value transferred within a configurable time window.

**Parameters:**
- `limit` -- maximum wei allowed within the window
- `window` -- duration in seconds over which the bucket linearly drains to zero

**How it works:**

The bucket fills as transactions are approved and drains linearly over the window period. The current usage after decay is:

```
currentUsage = used * (window - elapsed) / window
```

When `currentUsage + value > limit`, the transaction returns `Pending` (not `Rejected`). This is intentional -- the transaction can be re-evaluated later via `settle()` once enough time has passed for the bucket to drain.

Pending transactions **do not** consume bucket capacity. Only approved transactions fill the bucket, so a burst of over-limit transactions won't artificially inflate usage.

**Owner functions:**

```solidity
setConfig(uint256 _limit, uint256 _window)  // update rate limit parameters
```

**View functions:**

```solidity
currentUsage() returns (uint256)  // current bucket fill after linear decay
```

This is a state-modifying `check()` -- it updates `used` and `lastUpdated` when approving a transaction.

## Interfaces

### IRule

[`interfaces/universal/IRule.sol`](interfaces/universal/IRule.sol)

The interface that all compliance rules must implement. Contains a single method:

```solidity
function check(
    address _from,       // sender
    address _to,         // recipient
    uint256 _value,      // ETH value in wei
    uint64  _gasLimit,   // gas limit for execution
    bool    _isCreation, // contract creation flag
    bytes   _data,       // calldata
    uint256 _nonce       // transaction nonce
) external returns (ICompliance.Status);
```

A rule may be `view` (like `StaticAnalysisRule`) or state-modifying (like `RateLimitRule`). The `Compliance` contract calls `check()` on every registered rule for each transaction.

### ICompliance

[`interfaces/universal/ICompliance.sol`](interfaces/universal/ICompliance.sol)

The interface for the `Compliance` contract that aggregates rules and manages transaction lifecycle. Key methods:

| Method | Caller | Description |
|---|---|---|
| `check(...)` | Bridge | Evaluate a transaction against all rules |
| `approve(bytes32 _id)` | Owner | Manually approve a pending transaction |
| `reject(bytes32 _id)` | Owner | Manually reject a pending transaction |
| `settle(...)` | Anyone | Re-evaluate a pending transaction against rules |
| `addRule(address)` | Owner | Register a new rule |
| `removeRule(address)` | Owner | Unregister a rule |
| `status(bytes32 _id)` | Anyone | Query status and finality of a transaction |
| `rules()` | Anyone | List all registered rules |

The contract emits `Pending`, `Rejected`, `Approved`, and `Refunded` events that the operational scripts use for monitoring.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) -- `forge`, `cast`
- [just](https://github.com/casey/just#installation) -- command runner

## Quick Start

```bash
# Clone with submodules
git clone --recurse-submodules <repo-url>
cd rule-examples

# Build all contracts
just build

# Run the test suite
just test

# Format Solidity source files
just fmt
```

## Deployment

Create a `.env` file (the justfile loads it automatically):

```bash
ETH_RPC_URL=https://...
PRIVATE_KEY=0x...
COMPLIANCE_ADDRESS=0x...
```

Deploy contracts:

```bash
# StaticAnalysisRule -- pass the owner address
just deploy-static-analysis 0xOwnerAddress

# RateLimitRule -- pass owner, limit (wei), and window (seconds)
# Example: 10 ETH limit over a 1-hour window
just deploy-rate-limit 0xOwnerAddress 10000000000000000000 3600
```

After deployment, register the rule with the `Compliance` contract:

```bash
just add-rule 0xDeployedRuleAddress
```

## Operations

All operations are available as `just` recipes. Run `just --list` to see them all.

### Rule Management

```bash
just add-rule 0xRuleAddress        # Register a rule with the Compliance contract
just remove-rule 0xRuleAddress     # Remove a rule
just list-rules                    # List all registered rules
```

These wrap [`ops/manage-rules.sh`](ops/manage-rules.sh), which uses `cast send` / `cast call` under the hood.

### Transaction Management

```bash
just approve 0xTransactionId       # Approve a pending transaction
just reject 0xTransactionId        # Reject a pending transaction
just status 0xTransactionId        # Check transaction status and finality
```

The `status` command outputs:

```
Status: Approved|Pending|Rejected|Refunded (isFinal: true|false)
```

A finalized status cannot be changed by rule re-evaluation.

These wrap [`ops/manage-transactions.sh`](ops/manage-transactions.sh).

### Querying Events

```bash
just pending                       # Show pending transactions
just rejected                      # Show rejected transactions
just approved                      # Show approved transactions
just refunded                      # Show refunded transactions
just transactions                  # Show all transactions
```

Pending and rejected queries display a full table:

```
ID  FROM  TO  VALUE_ETH  GAS_LIMIT  NONCE  BLOCK  STATUS
```

Approved and refunded queries display a compact table:

```
ID  BLOCK  STATUS
```

You can narrow the block range with environment variables:

```bash
FROM_BLOCK=1000000 TO_BLOCK=2000000 just pending
```

These wrap [`ops/fetch-transactions.sh`](ops/fetch-transactions.sh), which uses `cast logs` and `jq` to decode events.

## Environment Variables

| Variable | Required | When | Description |
|---|---|---|---|
| `ETH_RPC_URL` | Yes | All operations | RPC endpoint URL |
| `PRIVATE_KEY` | Yes | Write operations | Private key for signing transactions |
| `COMPLIANCE_ADDRESS` | Yes | Ops scripts | Address of the deployed `Compliance` contract |
| `OWNER` | Yes | Deployment | Owner address for new rule contracts |
| `LIMIT` | Yes | RateLimitRule deploy | Maximum wei allowed within the rate limit window |
| `WINDOW` | Yes | RateLimitRule deploy | Drain period in seconds |
| `FROM_BLOCK` | No | Event queries | Starting block (default: `0`) |
| `TO_BLOCK` | No | Event queries | Ending block (default: `latest`) |

## Testing

The test suite covers both contracts thoroughly with unit tests, edge cases, and fuzz tests.

```bash
# Run all tests
just test

# Run with verbosity for detailed output
forge test -vvv

# Run a specific test file
forge test --match-path test/StaticAnalysisRule.t.sol

# Run a specific test
forge test --match-test test_decay_50percent
```

### StaticAnalysisRule tests ([`test/StaticAnalysisRule.t.sol`](test/StaticAnalysisRule.t.sol))

- Constructor correctness
- Access control on all six setter functions
- Clean state returns `Approved`
- Flagged entries return `Pending` per dimension (sender, target, selector)
- Rejected entries return `Rejected` per dimension
- Removing entries restores `Approved`
- `Rejected` priority over `Pending` across dimension combinations
- Edge cases: empty calldata, short calldata (<4 bytes), exactly 4 bytes, zero address
- Fuzz tests for random addresses

### RateLimitRule tests ([`test/RateLimitRule.t.sol`](test/RateLimitRule.t.sol))

- Constructor correctness and zero-window rejection
- Access control on `setConfig`
- Under/at/over limit behavior
- Cumulative usage tracking across multiple transactions
- Linear decay at 10%, 25%, 50%, 75%, 90%, 100%, and beyond-window time points
- Pending transactions do not consume bucket capacity
- Settle scenario: flagged then approved after decay
- Edge cases: zero value, zero limit, multiple checks in same block, `uint256.max` value
- Fuzz tests for decay linearity and bucket consumption invariants

## Project Structure

```
rule-examples/
├── src/                                    # Rule contract implementations
│   ├── StaticAnalysisRule.sol              # Deny-list based screening
│   └── RateLimitRule.sol                   # Leaky-bucket rate limiter
├── interfaces/universal/                   # Shared interfaces
│   ├── IRule.sol                           # Rule interface
│   └── ICompliance.sol                     # Compliance system interface
├── script/                                 # Foundry deployment scripts
│   ├── DeployStaticAnalysisRule.s.sol
│   └── DeployRateLimitRule.s.sol
├── test/                                   # Forge test suites
│   ├── StaticAnalysisRule.t.sol
│   └── RateLimitRule.t.sol
├── ops/                                    # Bash scripts for on-chain operations
│   ├── manage-rules.sh                     # Add / remove / list rules
│   ├── manage-transactions.sh              # Approve / reject / check status
│   └── fetch-transactions.sh               # Query compliance events
├── lib/forge-std/                          # Foundry standard library (submodule)
├── foundry.toml                            # Foundry configuration
└── justfile                                # Task runner recipes
```

## Transaction Lifecycle

```
                    ┌─────────────────────────────┐
                    │   Cross-chain transaction    │
                    │   arrives at the bridge      │
                    └──────────────┬──────────────┘
                                   │
                                   ▼
                    ┌─────────────────────────────┐
                    │   Compliance.check()         │
                    │   evaluates all rules        │
                    └──────────────┬──────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                     │
              ▼                    ▼                     ▼
        ┌──────────┐       ┌────────────┐        ┌───────────┐
        │ Approved │       │  Pending   │        │ Rejected  │
        │          │       │            │        │           │
        │ Tx goes  │       │ Tx held    │        │ ETH       │
        │ through  │       │ for review │        │ refunded  │
        │          │       │            │        │ on settle │  
        └──────────┘       └─────┬──────┘        └───────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
              owner calls  owner calls  anyone calls
              approve()    reject()     settle()
                    │            │            │
                    ▼            ▼            ▼
              ┌──────────┐ ┌─────────┐ ┌──────────────┐
              │ Approved │ │ Rejected│ │ Re-evaluates │
              │          │ │         │ │ rules; send  │
              │          │ │         │ │ ETH through  │
              │          │ │         │ │ or refund    │
              └──────────┘ └─────────┘ └──────────────┘
```

## Writing Your Own Rule

To create a custom rule, implement the `IRule` interface:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ICompliance } from "interfaces/universal/ICompliance.sol";
import { IRule } from "interfaces/universal/IRule.sol";

contract MyCustomRule is IRule {
    function check(
        address _from,
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes calldata _data,
        uint256 _nonce
    )
        external
        returns (ICompliance.Status)
    {
        // Your logic here.
        // Return Approved, Pending, or Rejected.
        // Do NOT return Refunded -- that is managed by the Compliance contract.
        return ICompliance.Status.Approved;
    }
}
```

Key considerations:

- Return `Pending` (not `Rejected`) if you want the transaction to be re-evaluable via `settle()`.
- A `view` rule is simpler and cheaper but cannot track state across calls. A state-modifying rule (like `RateLimitRule`) can maintain counters, timestamps, or other persistent data.
- The `Compliance` contract will revert if a rule returns `Refunded` -- that status is reserved for the compliance system itself.
