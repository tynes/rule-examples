// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { ICompliance } from "interfaces/universal/ICompliance.sol";
import { StaticAnalysisRule } from "../src/StaticAnalysisRule.sol";

contract StaticAnalysisRule_Test is Test {
    StaticAnalysisRule rule;
    address owner = makeAddr("owner");
    address nonOwner = makeAddr("nonOwner");
    address sender = makeAddr("sender");
    address target = makeAddr("target");
    bytes4 selector_ = bytes4(keccak256("transfer(address,uint256)"));

    function setUp() public {
        rule = new StaticAnalysisRule(owner);
    }

    /// @notice The constructor sets the owner correctly.
    function test_constructor_setsOwner() public view {
        assertEq(rule.owner(), owner);
    }

    // -------------------------------------------------------
    // Access control: all setters revert for non-owner
    // -------------------------------------------------------

    function test_setFlaggedSender_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(StaticAnalysisRule.StaticAnalysisRule_OnlyOwner.selector);
        rule.setFlaggedSender(sender, true);
    }

    function test_setFlaggedTarget_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(StaticAnalysisRule.StaticAnalysisRule_OnlyOwner.selector);
        rule.setFlaggedTarget(target, true);
    }

    function test_setFlaggedSelector_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(StaticAnalysisRule.StaticAnalysisRule_OnlyOwner.selector);
        rule.setFlaggedSelector(selector_, true);
    }

    function test_setRejectedSender_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(StaticAnalysisRule.StaticAnalysisRule_OnlyOwner.selector);
        rule.setRejectedSender(sender, true);
    }

    function test_setRejectedTarget_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(StaticAnalysisRule.StaticAnalysisRule_OnlyOwner.selector);
        rule.setRejectedTarget(target, true);
    }

    function test_setRejectedSelector_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(StaticAnalysisRule.StaticAnalysisRule_OnlyOwner.selector);
        rule.setRejectedSelector(selector_, true);
    }

    // -------------------------------------------------------
    // Clean state → Approved
    // -------------------------------------------------------

    function test_check_cleanState_returnsApproved() public view {
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, abi.encodeWithSelector(selector_), 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    // -------------------------------------------------------
    // Flagged (Pending) per dimension
    // -------------------------------------------------------

    function test_check_flaggedSender_returnsPending() public {
        vm.prank(owner);
        rule.setFlaggedSender(sender, true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));
    }

    function test_check_flaggedTarget_returnsPending() public {
        vm.prank(owner);
        rule.setFlaggedTarget(target, true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));
    }

    function test_check_flaggedSelector_returnsPending() public {
        vm.prank(owner);
        rule.setFlaggedSelector(selector_, true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, abi.encodeWithSelector(selector_), 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));
    }

    // -------------------------------------------------------
    // Rejected per dimension
    // -------------------------------------------------------

    function test_check_rejectedSender_returnsRejected() public {
        vm.prank(owner);
        rule.setRejectedSender(sender, true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }

    function test_check_rejectedTarget_returnsRejected() public {
        vm.prank(owner);
        rule.setRejectedTarget(target, true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }

    function test_check_rejectedSelector_returnsRejected() public {
        vm.prank(owner);
        rule.setRejectedSelector(selector_, true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, abi.encodeWithSelector(selector_), 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }

    // -------------------------------------------------------
    // Removal restores Approved
    // -------------------------------------------------------

    function test_check_unflaggedSender_returnsApproved() public {
        vm.startPrank(owner);
        rule.setFlaggedSender(sender, true);
        rule.setFlaggedSender(sender, false);
        vm.stopPrank();
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    function test_check_unrejectedTarget_returnsApproved() public {
        vm.startPrank(owner);
        rule.setRejectedTarget(target, true);
        rule.setRejectedTarget(target, false);
        vm.stopPrank();
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    // -------------------------------------------------------
    // Priority: Rejected wins over Pending
    // -------------------------------------------------------

    function test_check_rejectedWinsOverFlagged_sender() public {
        vm.startPrank(owner);
        rule.setFlaggedSender(sender, true);
        rule.setRejectedSender(sender, true);
        vm.stopPrank();
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }

    function test_check_rejectedTargetWinsOverFlaggedSender() public {
        vm.startPrank(owner);
        rule.setFlaggedSender(sender, true);
        rule.setRejectedTarget(target, true);
        vm.stopPrank();
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }

    function test_check_rejectedSelectorWinsOverFlaggedSender() public {
        vm.startPrank(owner);
        rule.setFlaggedSender(sender, true);
        rule.setRejectedSelector(selector_, true);
        vm.stopPrank();
        ICompliance.Status s =
            rule.check(sender, target, 1 ether, 100_000, false, abi.encodeWithSelector(selector_), 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }

    // -------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------

    function test_check_emptyCalldata_approved() public view {
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    function test_check_shortCalldata_selectorNotChecked() public {
        // Selector is flagged but calldata is only 3 bytes, so selector check is skipped.
        vm.prank(owner);
        rule.setFlaggedSelector(bytes4(hex"aabbccdd"), true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"aabbcc", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    function test_check_exactly4ByteCalldata() public {
        vm.prank(owner);
        rule.setFlaggedSelector(bytes4(hex"aabbccdd"), true);
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"aabbccdd", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));
    }

    function test_check_zeroAddress_sender() public {
        vm.prank(owner);
        rule.setRejectedSender(address(0), true);
        ICompliance.Status s = rule.check(address(0), target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }

    // -------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------

    function testFuzz_check_unflaggedAddress_returnsApproved(address _from, address _to) public view {
        ICompliance.Status s = rule.check(_from, _to, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    function testFuzz_check_flaggedSender_returnsPending(address _from) public {
        vm.prank(owner);
        rule.setFlaggedSender(_from, true);
        ICompliance.Status s = rule.check(_from, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));
    }

    function testFuzz_check_rejectedSender_returnsRejected(address _from) public {
        vm.prank(owner);
        rule.setRejectedSender(_from, true);
        ICompliance.Status s = rule.check(_from, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Rejected));
    }
}
