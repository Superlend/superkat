// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20
} from "../common/AggregationLayerVaultBase.t.sol";
import {TrackingRewardStreams} from "reward-streams/TrackingRewardStreams.sol";

contract StrategyRewardsE2ETest is AggregationLayerVaultBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testOptInStrategyRewards() public {
        vm.prank(manager);
        aggregationLayerVault.optInStrategyRewards(address(eTST));

        assertTrue(eTST.balanceForwarderEnabled(address(aggregationLayerVault)));
    }

    function testOptOutStrategyRewards() public {
        vm.prank(manager);
        aggregationLayerVault.optInStrategyRewards(address(eTST));
        assertTrue(eTST.balanceForwarderEnabled(address(aggregationLayerVault)));

        vm.prank(manager);
        aggregationLayerVault.optOutStrategyRewards(address(eTST));

        assertFalse(eTST.balanceForwarderEnabled(address(aggregationLayerVault)));
    }
}
