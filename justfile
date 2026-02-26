set dotenv-load

# ── Build & Test ──────────────────────────────

# Build all contracts
build:
    forge build

# Run the test suite
test:
    forge test

# Format Solidity source files
fmt:
    forge fmt

# ── Deploy ────────────────────────────────────

# Deploy StaticAnalysisRule (OWNER=address)
deploy-static-analysis owner:
    OWNER={{owner}} forge script script/DeployStaticAnalysisRule.s.sol \
        --rpc-url $ETH_RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast

# Deploy RateLimitRule (OWNER=address, LIMIT=wei, WINDOW=seconds)
deploy-rate-limit owner limit window:
    OWNER={{owner}} LIMIT={{limit}} WINDOW={{window}} \
        forge script script/DeployRateLimitRule.s.sol \
        --rpc-url $ETH_RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast

# ── Rule Management ───────────────────────────

# Add a rule to the compliance contract
add-rule rule:
    ./ops/manage-rules.sh add {{rule}}

# Remove a rule from the compliance contract
remove-rule rule:
    ./ops/manage-rules.sh remove {{rule}}

# List all registered rules
list-rules:
    ./ops/manage-rules.sh list

# ── Transaction Management ────────────────────

# Approve a pending transaction
approve id:
    ./ops/manage-transactions.sh approve {{id}}

# Reject a pending transaction
reject id:
    ./ops/manage-transactions.sh reject {{id}}

# Check status of a transaction
status id:
    ./ops/manage-transactions.sh status {{id}}

# ── Query ─────────────────────────────────────

# Show pending transactions
pending:
    ./ops/fetch-transactions.sh pending

# Show rejected transactions
rejected:
    ./ops/fetch-transactions.sh rejected

# Show approved transactions
approved:
    ./ops/fetch-transactions.sh approved

# Show refunded transactions
refunded:
    ./ops/fetch-transactions.sh refunded

# Show all transactions
transactions:
    ./ops/fetch-transactions.sh all
