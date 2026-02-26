// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ICompliance } from "interfaces/universal/ICompliance.sol";
import { IRule } from "interfaces/universal/IRule.sol";

/// @title StaticAnalysisRule
/// @notice An example IRule implementation that evaluates transactions against owner-configurable
///         deny lists. Supports three dimensions (sender, target, selector) and two severity
///         levels: flagged (returns Pending) and rejected (returns Rejected).
contract StaticAnalysisRule is IRule {
    /// @notice The owner of this rule, set at construction.
    address public immutable owner;

    /// @notice Senders that cause a Pending status.
    mapping(address => bool) public flaggedSenders;

    /// @notice Targets that cause a Pending status.
    mapping(address => bool) public flaggedTargets;

    /// @notice Function selectors that cause a Pending status.
    mapping(bytes4 => bool) public flaggedSelectors;

    /// @notice Senders that cause a Rejected status.
    mapping(address => bool) public rejectedSenders;

    /// @notice Targets that cause a Rejected status.
    mapping(address => bool) public rejectedTargets;

    /// @notice Function selectors that cause a Rejected status.
    mapping(bytes4 => bool) public rejectedSelectors;

    /// @notice Thrown when the caller is not the owner.
    error StaticAnalysisRule_OnlyOwner();

    /// @notice Restricts a function to the owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert StaticAnalysisRule_OnlyOwner();
        _;
    }

    /// @param _owner The address that will own this rule.
    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice Sets a sender as flagged or unflagged.
    function setFlaggedSender(address _sender, bool _flagged) external onlyOwner {
        flaggedSenders[_sender] = _flagged;
    }

    /// @notice Sets a target as flagged or unflagged.
    function setFlaggedTarget(address _target, bool _flagged) external onlyOwner {
        flaggedTargets[_target] = _flagged;
    }

    /// @notice Sets a function selector as flagged or unflagged.
    function setFlaggedSelector(bytes4 _selector, bool _flagged) external onlyOwner {
        flaggedSelectors[_selector] = _flagged;
    }

    /// @notice Sets a sender as rejected or not.
    function setRejectedSender(address _sender, bool _rejected) external onlyOwner {
        rejectedSenders[_sender] = _rejected;
    }

    /// @notice Sets a target as rejected or not.
    function setRejectedTarget(address _target, bool _rejected) external onlyOwner {
        rejectedTargets[_target] = _rejected;
    }

    /// @notice Sets a function selector as rejected or not.
    function setRejectedSelector(bytes4 _selector, bool _rejected) external onlyOwner {
        rejectedSelectors[_selector] = _rejected;
    }

    /// @inheritdoc IRule
    function check(
        address _from,
        address _to,
        uint256,
        uint64,
        bool,
        bytes calldata _data,
        uint256
    )
        external
        view
        returns (ICompliance.Status)
    {
        // Extract function selector if calldata is at least 4 bytes.
        bytes4 selector_;
        if (_data.length >= 4) {
            selector_ = bytes4(_data[:4]);
        }

        // Rejected takes priority over Pending.
        if (rejectedSenders[_from] || rejectedTargets[_to]) {
            return ICompliance.Status.Rejected;
        }
        if (_data.length >= 4 && rejectedSelectors[selector_]) {
            return ICompliance.Status.Rejected;
        }

        // Pending (flagged).
        if (flaggedSenders[_from] || flaggedTargets[_to]) {
            return ICompliance.Status.Pending;
        }
        if (_data.length >= 4 && flaggedSelectors[selector_]) {
            return ICompliance.Status.Pending;
        }

        return ICompliance.Status.Approved;
    }
}
