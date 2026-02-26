// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { ICompliance } from "interfaces/universal/ICompliance.sol";
import { RateLimitRule } from "../src/RateLimitRule.sol";

contract RateLimitRule_Test is Test {
    RateLimitRule rule;
    address owner = makeAddr("owner");
    address nonOwner = makeAddr("nonOwner");
    address sender = makeAddr("sender");
    address target = makeAddr("target");

    uint256 constant LIMIT = 10 ether;
    uint256 constant WINDOW = 1000; // seconds

    function setUp() public {
        rule = new RateLimitRule(owner, LIMIT, WINDOW);
    }

    // -------------------------------------------------------
    // Constructor
    // -------------------------------------------------------

    function test_constructor_setsParams() public view {
        assertEq(rule.owner(), owner);
        assertEq(rule.limit(), LIMIT);
        assertEq(rule.window(), WINDOW);
    }

    function test_constructor_zeroWindow_reverts() public {
        vm.expectRevert(RateLimitRule.RateLimitRule_ZeroWindow.selector);
        new RateLimitRule(owner, LIMIT, 0);
    }

    // -------------------------------------------------------
    // Access control
    // -------------------------------------------------------

    function test_setConfig_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(RateLimitRule.RateLimitRule_OnlyOwner.selector);
        rule.setConfig(1 ether, 500);
    }

    function test_setConfig_zeroWindow_reverts() public {
        vm.prank(owner);
        vm.expectRevert(RateLimitRule.RateLimitRule_ZeroWindow.selector);
        rule.setConfig(1 ether, 0);
    }

    function test_setConfig_updatesParams() public {
        vm.prank(owner);
        rule.setConfig(5 ether, 2000);
        assertEq(rule.limit(), 5 ether);
        assertEq(rule.window(), 2000);
    }

    // -------------------------------------------------------
    // Under / at / over limit
    // -------------------------------------------------------

    function test_check_underLimit_approved() public {
        ICompliance.Status s = rule.check(sender, target, 5 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    function test_check_atLimit_approved() public {
        ICompliance.Status s = rule.check(sender, target, LIMIT, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    function test_check_overLimit_pending() public {
        ICompliance.Status s = rule.check(sender, target, LIMIT + 1, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));
    }

    // -------------------------------------------------------
    // Cumulative usage
    // -------------------------------------------------------

    function test_check_cumulativeUsage() public {
        // First call: 6 ether (approved, 6/10 used)
        ICompliance.Status s1 = rule.check(sender, target, 6 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s1), uint8(ICompliance.Status.Approved));

        // Second call: 4 ether (approved, exactly at 10/10)
        ICompliance.Status s2 = rule.check(sender, target, 4 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s2), uint8(ICompliance.Status.Approved));

        // Third call: 1 wei over limit
        ICompliance.Status s3 = rule.check(sender, target, 1, 100_000, false, hex"", 0);
        assertEq(uint8(s3), uint8(ICompliance.Status.Pending));
    }

    // -------------------------------------------------------
    // Linear decay at various time points
    // -------------------------------------------------------

    function test_decay_10percent() public {
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + WINDOW / 10); // 10% elapsed → 90% remaining = 9 ether
        assertEq(rule.currentUsage(), 9 ether);
    }

    function test_decay_25percent() public {
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + WINDOW / 4); // 25% elapsed → 75% remaining = 7.5 ether
        assertEq(rule.currentUsage(), 7.5 ether);
    }

    function test_decay_50percent() public {
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + WINDOW / 2); // 50% elapsed → 50% remaining = 5 ether
        assertEq(rule.currentUsage(), 5 ether);
    }

    function test_decay_75percent() public {
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + (WINDOW * 3) / 4); // 75% elapsed → 25% remaining = 2.5 ether
        assertEq(rule.currentUsage(), 2.5 ether);
    }

    function test_decay_90percent() public {
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + (WINDOW * 9) / 10); // 90% elapsed → 10% remaining = 1 ether
        assertEq(rule.currentUsage(), 1 ether);
    }

    function test_decay_fullWindow() public {
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + WINDOW); // 100% elapsed → 0 remaining
        assertEq(rule.currentUsage(), 0);
    }

    function test_decay_beyondWindow() public {
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + WINDOW * 2); // Well past window
        assertEq(rule.currentUsage(), 0);
    }

    // -------------------------------------------------------
    // Flagged tx does NOT consume bucket capacity
    // -------------------------------------------------------

    function test_check_pendingDoesNotConsumeBucket() public {
        _fillBucket(LIMIT);

        // Bucket is full. Another 1 ether should be pending.
        ICompliance.Status s = rule.check(sender, target, 1 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));

        // Bucket should still be at LIMIT, not LIMIT + 1 ether.
        assertEq(rule.used(), LIMIT);
    }

    // -------------------------------------------------------
    // Re-evaluation after decay (settle scenario)
    // -------------------------------------------------------

    function test_settleScenario_flaggedThenApprovedAfterDecay() public {
        _fillBucket(LIMIT);

        // Over limit → Pending
        ICompliance.Status s1 = rule.check(sender, target, 2 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s1), uint8(ICompliance.Status.Pending));

        // Wait for 50% decay: 10 ether → 5 ether used. Now 2 ether fits (5 + 2 = 7 <= 10).
        vm.warp(block.timestamp + WINDOW / 2);

        ICompliance.Status s2 = rule.check(sender, target, 2 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s2), uint8(ICompliance.Status.Approved));
    }

    // -------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------

    function test_check_zeroValue_approved() public {
        ICompliance.Status s = rule.check(sender, target, 0, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Approved));
    }

    function test_check_zeroLimit() public {
        vm.prank(owner);
        rule.setConfig(0, WINDOW);

        // Even 0 value should be approved (0 + 0 = 0 <= 0)
        ICompliance.Status s1 = rule.check(sender, target, 0, 100_000, false, hex"", 0);
        assertEq(uint8(s1), uint8(ICompliance.Status.Approved));

        // Any positive value should be pending
        ICompliance.Status s2 = rule.check(sender, target, 1, 100_000, false, hex"", 0);
        assertEq(uint8(s2), uint8(ICompliance.Status.Pending));
    }

    function test_check_sameTimestamp_multiCheck() public {
        // Multiple checks in the same block
        ICompliance.Status s1 = rule.check(sender, target, 3 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s1), uint8(ICompliance.Status.Approved));

        ICompliance.Status s2 = rule.check(sender, target, 3 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s2), uint8(ICompliance.Status.Approved));

        ICompliance.Status s3 = rule.check(sender, target, 3 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s3), uint8(ICompliance.Status.Approved));

        // 9 used, only 1 ether left
        ICompliance.Status s4 = rule.check(sender, target, 2 ether, 100_000, false, hex"", 0);
        assertEq(uint8(s4), uint8(ICompliance.Status.Pending));
    }

    function test_check_veryLargeValue_pending() public {
        ICompliance.Status s = rule.check(sender, target, type(uint256).max, 100_000, false, hex"", 0);
        assertEq(uint8(s), uint8(ICompliance.Status.Pending));
    }

    // -------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------

    function testFuzz_decay_linearity(uint256 _elapsed) public {
        _elapsed = bound(_elapsed, 0, WINDOW);
        _fillBucket(LIMIT);
        vm.warp(block.timestamp + _elapsed);
        uint256 expected = LIMIT * (WINDOW - _elapsed) / WINDOW;
        assertEq(rule.currentUsage(), expected);
    }

    function testFuzz_check_pendingDoesNotConsumeBucket(uint256 _extra) public {
        _extra = bound(_extra, 1, type(uint128).max);
        _fillBucket(LIMIT);
        uint256 usedBefore = rule.used();
        rule.check(sender, target, _extra, 100_000, false, hex"", 0);
        assertEq(rule.used(), usedBefore);
    }

    // -------------------------------------------------------
    // Helpers
    // -------------------------------------------------------

    function _fillBucket(uint256 _amount) internal {
        rule.check(sender, target, _amount, 100_000, false, hex"", 0);
    }
}
