// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract StrategyUtil is Test {
    address[] public strategies;

    function includeStrategy(address _strategy) external {
        strategies.push(_strategy);
    }

    function fetchStrategy(uint256 _strategyIndexSeed) external view returns (address) {
        return strategies[bound(_strategyIndexSeed, 0, strategies.length - 1)];
    }

    function fetchExactStrategy(uint256 _strategyIndex) external view returns (address) {
        return strategies[_strategyIndex];
    }
}
