// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    YieldAggregatorBase,
    YieldAggregator,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20
} from "../common/YieldAggregatorBase.t.sol";
import {TrackingRewardStreams} from "reward-streams/src/TrackingRewardStreams.sol";

contract StrategyRewardsE2ETest is YieldAggregatorBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testOptInStrategyRewards() public {
        vm.prank(manager);
        eulerYieldAggregatorVault.optInStrategyRewards(address(eTST));

        assertTrue(eTST.balanceForwarderEnabled(address(eulerYieldAggregatorVault)));
    }

    function testOptOutStrategyRewards() public {
        vm.prank(manager);
        eulerYieldAggregatorVault.optInStrategyRewards(address(eTST));
        assertTrue(eTST.balanceForwarderEnabled(address(eulerYieldAggregatorVault)));

        vm.prank(manager);
        eulerYieldAggregatorVault.optOutStrategyRewards(address(eTST));

        assertFalse(eTST.balanceForwarderEnabled(address(eulerYieldAggregatorVault)));
    }
}
