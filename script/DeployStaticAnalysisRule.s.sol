// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { StaticAnalysisRule } from "../src/StaticAnalysisRule.sol";

contract DeployStaticAnalysisRule is Script {
    function run() external {
        address owner = vm.envAddress("OWNER");

        vm.broadcast();
        new StaticAnalysisRule(owner);
    }
}
