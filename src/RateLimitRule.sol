// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ICompliance } from "interfaces/universal/ICompliance.sol";
import { IRule } from "interfaces/universal/IRule.sol";

/// @title RateLimitRule
/// @notice An example IRule implementation that enforces a leaky-bucket rate limit on ETH value.
///         When the projected bucket usage exceeds the limit the transaction is flagged as Pending
///         (not Rejected) so that it can be re-evaluated later via settle() once the bucket has
///         drained sufficiently.
contract RateLimitRule is IRule {
    /// @notice The owner of this rule, set at construction.
    address public immutable owner;

    /// @notice Maximum wei allowed within the window.
    uint256 public limit;

    /// @notice Duration in seconds over which the bucket linearly drains.
    uint256 public window;

    /// @notice Current fill level of the bucket (before decay).
    uint256 public used;

    /// @notice Timestamp of the last bucket update.
    uint256 public lastUpdated;

    /// @notice Thrown when the caller is not the owner.
    error RateLimitRule_OnlyOwner();

    /// @notice Thrown when a zero window is provided.
    error RateLimitRule_ZeroWindow();

    /// @notice Restricts a function to the owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert RateLimitRule_OnlyOwner();
        _;
    }

    /// @param _owner  The address that will own this rule.
    /// @param _limit  Maximum wei allowed within the window.
    /// @param _window Duration in seconds over which the bucket drains.
    constructor(address _owner, uint256 _limit, uint256 _window) {
        if (_window == 0) revert RateLimitRule_ZeroWindow();
        owner = _owner;
        limit = _limit;
        window = _window;
        lastUpdated = block.timestamp;
    }

    /// @notice Updates the rate limit configuration. Only callable by the owner.
    /// @param _limit  New maximum wei allowed within the window.
    /// @param _window New drain period in seconds.
    function setConfig(uint256 _limit, uint256 _window) external onlyOwner {
        if (_window == 0) revert RateLimitRule_ZeroWindow();
        limit = _limit;
        window = _window;
    }

    /// @notice Returns the current bucket usage after applying linear decay.
    /// @return The decayed usage in wei.
    function currentUsage() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastUpdated;
        if (elapsed >= window) return 0;
        return used * (window - elapsed) / window;
    }

    /// @inheritdoc IRule
    function check(
        address,
        address,
        uint256 _value,
        uint64,
        bool,
        bytes calldata,
        uint256
    )
        external
        returns (ICompliance.Status)
    {
        uint256 decayed = currentUsage();
        uint256 projected = decayed + _value;

        if (projected > limit) {
            // Do NOT update the bucket. The value is not consumed so that re-evaluation
            // after time has passed (via settle) can approve the transaction once the
            // bucket has drained enough.
            return ICompliance.Status.Pending;
        }

        used = projected;
        lastUpdated = block.timestamp;
        return ICompliance.Status.Approved;
    }
}
