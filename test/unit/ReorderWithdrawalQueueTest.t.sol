// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    IEVault,
    WithdrawalQueue,
    ErrorsLib
} from "../common/EulerAggregationVaultBase.t.sol";

contract ReorderWithdrawalQueueTest is EulerAggregationVaultBase {
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
        assertEq(eulerAggregationVault.getStrategy(_getWithdrawalQueue()[0]).allocationPoints, eTSTAllocationPoints);
        assertEq(
            eulerAggregationVault.getStrategy(_getWithdrawalQueue()[1]).allocationPoints, eTSTsecondaryAllocationPoints
        );

        vm.prank(manager);
        eulerAggregationVault.reorderWithdrawalQueue(0, 1);

        assertEq(
            eulerAggregationVault.getStrategy(_getWithdrawalQueue()[0]).allocationPoints, eTSTsecondaryAllocationPoints
        );
        assertEq(eulerAggregationVault.getStrategy(_getWithdrawalQueue()[1]).allocationPoints, eTSTAllocationPoints);
    }

    function testReorderWithdrawalQueueWhenOutOfBounds() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.OutOfBounds.selector);
        eulerAggregationVault.reorderWithdrawalQueue(0, 3);
        vm.stopPrank();
    }

    function testReorderWithdrawalQueueWhenSameIndex() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.SameIndexes.selector);
        eulerAggregationVault.reorderWithdrawalQueue(0, 0);
        vm.stopPrank();
    }
}
