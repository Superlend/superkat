// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// echidna erc-4626 properties tests
import {CryticERC4626PropertyTests} from "crytic-properties/ERC4626/ERC4626PropertyTests.sol";
// contracts
import {EulerAggregationVault} from "../../src/core/EulerAggregationVault.sol";
import {Rebalancer} from "../../src/plugin/Rebalancer.sol";
import {Hooks} from "../../src/core/module/Hooks.sol";
import {Rewards} from "../../src/core/module/Rewards.sol";
import {Fee} from "../../src/core/module/Fee.sol";
import {EulerAggregationVaultFactory} from "../../src/core/EulerAggregationVaultFactory.sol";
import {WithdrawalQueue} from "../../src/plugin/WithdrawalQueue.sol";
import {AllocationPoints} from "../../src/core/module/AllocationPoints.sol";
import {TestERC20Token} from "crytic-properties/ERC4626/util/TestERC20Token.sol";

contract CryticERC4626TestsHarness is CryticERC4626PropertyTests {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    // core modules
    Rewards rewardsImpl;
    Hooks hooksImpl;
    Fee feeModuleImpl;
    AllocationPoints allocationPointsModuleImpl;
    // plugins
    Rebalancer rebalancerPlugin;
    WithdrawalQueue withdrawalQueuePluginImpl;

    EulerAggregationVaultFactory eulerAggregationVaultFactory;
    EulerAggregationVault eulerAggregationVault;

    constructor() {
        rewardsImpl = new Rewards();
        hooksImpl = new Hooks();
        feeModuleImpl = new Fee();
        allocationPointsModuleImpl = new AllocationPoints();

        rebalancerPlugin = new Rebalancer();
        withdrawalQueuePluginImpl = new WithdrawalQueue();

        EulerAggregationVaultFactory.FactoryParams memory factoryParams = EulerAggregationVaultFactory.FactoryParams({
            balanceTracker: address(0),
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            allocationPointsModuleImpl: address(allocationPointsModuleImpl),
            rebalancer: address(rebalancerPlugin),
            withdrawalQueueImpl: address(withdrawalQueuePluginImpl)
        });
        eulerAggregationVaultFactory = new EulerAggregationVaultFactory(factoryParams);

        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        address _vault = eulerAggregationVaultFactory.deployEulerAggregationVault(
            address(_asset), "TT_Agg", "TT_Agg", CASH_RESERVE_ALLOCATION_POINTS
        );

        initialize(address(_vault), address(_asset), false);
    }
}
