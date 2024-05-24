// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    FourSixTwoSixAggBase,
    FourSixTwoSixAgg,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20
} from "../common/FourSixTwoSixAggBase.t.sol";
import {TrackingRewardStreams} from "reward-streams/TrackingRewardStreams.sol";

contract BalanceForwarderE2ETest is FourSixTwoSixAggBase {
    uint256 user1InitialBalance = 100000e18;

    address trackingReward;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(deployer);
        trackingReward = address(new TrackingRewardStreams(address(evc), 2 weeks));

        fourSixTwoSixAgg = new FourSixTwoSixAgg(
            evc,
            trackingReward,
            address(assetTST),
            "assetTST_Agg",
            "assetTST_Agg",
            CASH_RESERVE_ALLOCATION_POINTS,
            new address[](0),
            new uint256[](0)
        );

        // grant admin roles to deployer
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE_ADMIN_ROLE(), deployer);
        // grant roles to manager
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE(), manager);
        vm.stopPrank();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(address(fourSixTwoSixAgg.balanceTracker()), trackingReward);
    }
}
