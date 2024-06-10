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

contract StrategyCapE2ETest is FourSixTwoSixAggBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetCap() public {
        uint256 cap = 1000000e18;

        assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).cap, 0);

        vm.prank(manager);
        fourSixTwoSixAgg.setStrategyCap(address(eTST), cap);

        FourSixTwoSixAgg.Strategy memory strategy = fourSixTwoSixAgg.getStrategy(address(eTST));

        assertEq(strategy.cap, cap);
    }

    function testSetCapForInactiveStrategy() public {
        uint256 cap = 1000000e18;

        vm.prank(manager);
        vm.expectRevert(FourSixTwoSixAgg.InactiveStrategy.selector);
        fourSixTwoSixAgg.setStrategyCap(address(0x2), cap);
    }
}
