// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FourSixTwoSixAggBase, FourSixTwoSixAgg, IEVault} from "../common/FourSixTwoSixAggBase.t.sol";

contract ReorderWithdrawalQueueTest is FourSixTwoSixAggBase {
    uint256 eTSTAllocationPoints = 500e18;
    uint256 eTSTsecondaryAllocationPoints = 700e18;

    IEVault eTSTsecondary;

    function setUp() public virtual override {
        super.setUp();

        _addStrategy(manager, address(eTST), eTSTAllocationPoints);

        {
            eTSTsecondary = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );
        }
        _addStrategy(manager, address(eTSTsecondary), eTSTsecondaryAllocationPoints);
    }

    function testReorderWithdrawalQueue() public {
        assertEq(
            fourSixTwoSixAgg.getStrategy(fourSixTwoSixAgg.withdrawalQueue(0)).allocationPoints, eTSTAllocationPoints
        );
        assertEq(
            fourSixTwoSixAgg.getStrategy(fourSixTwoSixAgg.withdrawalQueue(1)).allocationPoints,
            eTSTsecondaryAllocationPoints
        );

        vm.prank(manager);
        fourSixTwoSixAgg.reorderWithdrawalQueue(0, 1);

        assertEq(
            fourSixTwoSixAgg.getStrategy(fourSixTwoSixAgg.withdrawalQueue(0)).allocationPoints,
            eTSTsecondaryAllocationPoints
        );
        assertEq(
            fourSixTwoSixAgg.getStrategy(fourSixTwoSixAgg.withdrawalQueue(1)).allocationPoints, eTSTAllocationPoints
        );
    }

    function testReorderWithdrawalQueueWhenOutOfBounds() public {
        vm.startPrank(manager);
        vm.expectRevert(FourSixTwoSixAgg.OutOfBounds.selector);
        fourSixTwoSixAgg.reorderWithdrawalQueue(0, 3);
        vm.stopPrank();
    }

    function testReorderWithdrawalQueueWhenSameIndex() public {
        vm.startPrank(manager);
        vm.expectRevert(FourSixTwoSixAgg.SameIndexes.selector);
        fourSixTwoSixAgg.reorderWithdrawalQueue(1, 1);
        vm.stopPrank();
    }
}
