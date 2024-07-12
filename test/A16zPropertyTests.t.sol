// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// a16z properties tests
import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
// contracts
import {EulerAggregationVault} from "../src/core/EulerAggregationVault.sol";
import {Rebalancer} from "../src/plugin/Rebalancer.sol";
import {Hooks} from "../src/core/module/Hooks.sol";
import {Rewards} from "../src/core/module/Rewards.sol";
import {Fee} from "../src/core/module/Fee.sol";
import {EulerAggregationVaultFactory} from "../src/core/EulerAggregationVaultFactory.sol";
import {WithdrawalQueue} from "../src/plugin/WithdrawalQueue.sol";
import {AllocationPoints} from "../src/core/module/AllocationPoints.sol";
// mocks
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract A16zPropertyTests is ERC4626Test {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address public factoryOwner;

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

    function setUp() public override {
        factoryOwner = makeAddr("FACTORY_OWNER");

        rewardsImpl = new Rewards();
        hooksImpl = new Hooks();
        feeModuleImpl = new Fee();
        allocationPointsModuleImpl = new AllocationPoints();

        rebalancerPlugin = new Rebalancer();
        withdrawalQueuePluginImpl = new WithdrawalQueue();

        EulerAggregationVaultFactory.FactoryParams memory factoryParams = EulerAggregationVaultFactory.FactoryParams({
            owner: factoryOwner,
            balanceTracker: address(0),
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            allocationPointsModuleImpl: address(allocationPointsModuleImpl),
            rebalancer: address(rebalancerPlugin)
        });
        eulerAggregationVaultFactory = new EulerAggregationVaultFactory(factoryParams);
        vm.prank(factoryOwner);
        eulerAggregationVaultFactory.whitelistWithdrawalQueueImpl(address(withdrawalQueuePluginImpl));

        _underlying_ = address(new ERC20Mock());
        _vault_ = eulerAggregationVaultFactory.deployEulerAggregationVault(
            address(withdrawalQueuePluginImpl), _underlying_, "E20M_Agg", "E20M_Agg", CASH_RESERVE_ALLOCATION_POINTS
        );
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }

    function testToAvoidCoverage() public pure {
        return;
    }
}
