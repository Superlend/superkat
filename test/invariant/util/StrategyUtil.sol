// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract StrategyUtil is Test {
    address[] public nonActiveStrategies;
    address[] public activeStrategies;
    address[] public emergencyStrategies;

    function includeStrategy(address _strategy) external {
        nonActiveStrategies.push(_strategy);
    }

    function fromNonActiveToActive(address _strategy) external {
        uint256 lastStrategyIndex = nonActiveStrategies.length - 1;
        for (uint256 i = 0; i < lastStrategyIndex; ++i) {
            if (nonActiveStrategies[i] == _strategy) {
                nonActiveStrategies[i] = nonActiveStrategies[lastStrategyIndex];

                break;
            }
        }
        nonActiveStrategies.pop();

        activeStrategies.push(_strategy);
    }

    function fromActiveToEmergency(address _strategy) external {
        uint256 lastStrategyIndex = activeStrategies.length - 1;
        for (uint256 i = 0; i < lastStrategyIndex; ++i) {
            if (activeStrategies[i] == _strategy) {
                activeStrategies[i] = activeStrategies[lastStrategyIndex];

                break;
            }
        }
        activeStrategies.pop();

        emergencyStrategies.push(_strategy);
    }

    function fromEmergencyToActive(address _strategy) external {
        uint256 lastStrategyIndex = emergencyStrategies.length - 1;
        for (uint256 i = 0; i < lastStrategyIndex; ++i) {
            if (emergencyStrategies[i] == _strategy) {
                emergencyStrategies[i] = emergencyStrategies[lastStrategyIndex];

                break;
            }
        }
        emergencyStrategies.pop();

        activeStrategies.push(_strategy);
    }

    function fromActiveToNonActive(address _strategy) external {
        uint256 lastStrategyIndex = activeStrategies.length - 1;
        for (uint256 i = 0; i < lastStrategyIndex; ++i) {
            if (activeStrategies[i] == _strategy) {
                activeStrategies[i] = activeStrategies[lastStrategyIndex];

                break;
            }
        }
        activeStrategies.pop();

        nonActiveStrategies.push(_strategy);
    }

    function fetchNonActiveStrategy(uint256 _strategyIndexSeed) external view returns (address) {
        if (nonActiveStrategies.length == 0) return address(0);

        uint256 index = bound(_strategyIndexSeed, 0, nonActiveStrategies.length - 1);
        return nonActiveStrategies[index];
    }

    function fetchActiveStrategy(uint256 _strategyIndexSeed) external view returns (address) {
        if (activeStrategies.length == 0) return address(0);

        uint256 index = bound(_strategyIndexSeed, 0, activeStrategies.length - 1);
        return activeStrategies[index];
    }

    function fetchEmergencyStrategy(uint256 _strategyIndexSeed) external view returns (address) {
        if (emergencyStrategies.length == 0) return address(0);

        uint256 index = bound(_strategyIndexSeed, 0, emergencyStrategies.length - 1);
        return emergencyStrategies[index];
    }

    function fetchActiveOrEmergencyStrategy(uint256 _strategyIndexSeed, bool _isInitiallyActive)
        external
        view
        returns (address)
    {
        address strategy;
        if (_isInitiallyActive) {
            if (activeStrategies.length != 0) {
                uint256 index = bound(_strategyIndexSeed, 0, activeStrategies.length - 1);
                strategy = activeStrategies[index];
            }
        } else {
            if (emergencyStrategies.length != 0) {
                uint256 index = bound(_strategyIndexSeed, 0, emergencyStrategies.length - 1);
                strategy = emergencyStrategies[index];
            }
        }

        return strategy;
    }
}
