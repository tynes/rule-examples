// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { RateLimitRule } from "../src/RateLimitRule.sol";

contract DeployRateLimitRule is Script {
    function run() external {
        address owner = vm.envAddress("OWNER");
        uint256 limit = vm.envUint("LIMIT");
        uint256 window = vm.envUint("WINDOW");

        vm.broadcast();
        new RateLimitRule(owner, limit, window);
    }
}
