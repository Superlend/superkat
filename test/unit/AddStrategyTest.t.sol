// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FourSixTwoSixAggBase, FourSixTwoSixAgg} from "./FourSixTwoSixAggBase.t.sol";

contract AddStrategyTest is FourSixTwoSixAggBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testAddStrategy() public {
        uint256 allocationPoints = type(uint120).max;

        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), 0);

        _addStrategy(manager, address(eTST), allocationPoints);

        assertEq(fourSixTwoSixAgg.totalAllocationPoints(), allocationPoints);
        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), 1);
    }

    function testAddStrategy_FromUnauthorizedAddress() public {
        uint256 allocationPoints = type(uint120).max;

        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), 0);

        vm.expectRevert();
        _addStrategy(deployer, address(eTST), allocationPoints);
    }

    function testAddStrategy_WithInvalidAsset() public {
        uint256 allocationPoints = type(uint120).max;

        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), 0);

        vm.expectRevert();
        _addStrategy(manager, address(eTST2), allocationPoints);
    }

    function testAddStrategy_AlreadyAddedStrategy() public {
        uint256 allocationPoints = type(uint120).max;

        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), 0);

        _addStrategy(manager, address(eTST), allocationPoints);

        assertEq(fourSixTwoSixAgg.totalAllocationPoints(), allocationPoints);
        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), 1);

        vm.expectRevert();
        _addStrategy(manager, address(eTST), allocationPoints);
    }
}
