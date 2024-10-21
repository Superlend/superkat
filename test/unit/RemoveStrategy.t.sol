// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract RemoveStrategyTest is EulerEarnBase {
    uint256 strategyAllocationPoints;

    IEVault anotherStrategy;

    function setUp() public virtual override {
        super.setUp();

        strategyAllocationPoints = 1000e18;
        _addStrategy(manager, address(eTST), strategyAllocationPoints);
    }

    function testRemoveStrategy() public {
        uint256 totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerEulerEarnVault.removeStrategy(address(eTST));

        IEulerEarn.Strategy memory strategyAfter = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(strategyAfter.status == IEulerEarn.StrategyStatus.Inactive, true);
        assertEq(strategyAfter.allocationPoints, 0);
        assertEq(eulerEulerEarnVault.totalAllocationPoints(), totalAllocationPointsBefore - strategyAllocationPoints);
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore - 1);
    }

    function testRemoveStrategyWithMultipleStrategies() public {
        anotherStrategy = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        _addStrategy(manager, address(anotherStrategy), strategyAllocationPoints);

        uint256 totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerEulerEarnVault.removeStrategy(address(eTST));

        IEulerEarn.Strategy memory strategyAfter = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(strategyAfter.status == IEulerEarn.StrategyStatus.Inactive, true);
        assertEq(strategyAfter.allocationPoints, 0);
        assertEq(eulerEulerEarnVault.totalAllocationPoints(), totalAllocationPointsBefore - strategyAllocationPoints);
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore - 1);
    }

    function testRemoveStrategy_WithdrawalQueueOrdering() public {
        address strategy1 =
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount));
        address strategy2 =
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount));
        address strategy3 =
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount));

        _addStrategy(manager, strategy1, strategyAllocationPoints);
        _addStrategy(manager, strategy2, strategyAllocationPoints);
        _addStrategy(manager, strategy3, strategyAllocationPoints);

        address[] memory withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 4);
        assertEq(withdrawalQueue[0], address(eTST));
        assertEq(withdrawalQueue[1], strategy1);
        assertEq(withdrawalQueue[2], strategy2);
        assertEq(withdrawalQueue[3], strategy3);

        vm.prank(manager);
        eulerEulerEarnVault.removeStrategy(strategy2);

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 3);
        assertEq(withdrawalQueue[0], address(eTST));
        assertEq(withdrawalQueue[1], strategy1);
        assertEq(withdrawalQueue[2], strategy3);

        vm.prank(manager);
        eulerEulerEarnVault.removeStrategy(strategy3);

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 2);
        assertEq(withdrawalQueue[0], address(eTST));
        assertEq(withdrawalQueue[1], strategy1);

        vm.prank(manager);
        eulerEulerEarnVault.removeStrategy(address(eTST));

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 1);
        assertEq(withdrawalQueue[0], strategy1);

        vm.prank(manager);
        eulerEulerEarnVault.removeStrategy(strategy1);

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 0);
    }

    function testRemoveStrategy_fromUnauthorized() public {
        vm.prank(deployer);
        vm.expectRevert();
        eulerEulerEarnVault.removeStrategy(address(eTST));
    }

    function testRemoveStrategy_StrategyShouldBeActive() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerEulerEarnVault.removeStrategy(address(eTST2));
    }

    function testRemoveCashReserveStrategy() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.CanNotRemoveCashReserve.selector);
        eulerEulerEarnVault.removeStrategy(address(0));
    }

    function testRemoveStrategyWithAllocatedAmount() public {
        uint256 amountToDeposit = 10000e18;
        assetTST.mint(user1, amountToDeposit);

        // deposit into EulerEarn
        {
            uint256 balanceBefore = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
            eulerEulerEarnVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerEulerEarnVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();

            vm.prank(manager);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.CanNotRemoveStrategyWithAllocatedAmount.selector);
        eulerEulerEarnVault.removeStrategy(address(eTST));
    }
}
