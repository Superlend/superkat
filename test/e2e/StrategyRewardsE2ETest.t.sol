// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20
} from "../common/EulerAggregationVaultBase.t.sol";
import {TrackingRewardStreams} from "reward-streams/TrackingRewardStreams.sol";

contract StrategyRewardsE2ETest is EulerAggregationVaultBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testOptInStrategyRewards() public {
        vm.prank(manager);
        eulerAggregationVault.optInStrategyRewards(address(eTST));

        assertTrue(eTST.balanceForwarderEnabled(address(eulerAggregationVault)));
    }

    function testOptOutStrategyRewards() public {
        vm.prank(manager);
        eulerAggregationVault.optInStrategyRewards(address(eTST));
        assertTrue(eTST.balanceForwarderEnabled(address(eulerAggregationVault)));

        vm.prank(manager);
        eulerAggregationVault.optOutStrategyRewards(address(eTST));

        assertFalse(eTST.balanceForwarderEnabled(address(eulerAggregationVault)));
    }
}
