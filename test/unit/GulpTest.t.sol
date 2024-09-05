// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract GulpTest is YieldAggregatorBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
            eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(eulerYieldAggregatorVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedStrategyCash);
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }
    }

    function testGulpAfterNegativeYieldEqualToInterestLeft() public {
        eulerYieldAggregatorVault.gulp();
        (,, uint168 interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);
        assertEq(interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerYieldAggregatorVault.gulp();
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerYieldAggregatorVault));
        }
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 23809523809523809523);
        eulerYieldAggregatorVault.gulp();
        (,, interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();
        assertEq(interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerYieldAggregatorVault.gulp();
        (,, interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();

        // mock a decrease of strategy balance by interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - interestLeft;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerYieldAggregatorVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();
    }

    function testGulpAfterNegativeYieldBiggerThanInterestLeft() public {
        eulerYieldAggregatorVault.gulp();
        (,, uint168 interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);
        assertEq(interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerYieldAggregatorVault.gulp();
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerYieldAggregatorVault));
        }
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        assertEq(eulerYieldAggregatorVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerYieldAggregatorVault.interestAccrued(), 23809523809523809523);
        eulerYieldAggregatorVault.gulp();
        (,, interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();
        assertEq(interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerYieldAggregatorVault.gulp();
        (,, interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();

        // mock a decrease of strategy balance by interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - (interestLeft * 2);
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerYieldAggregatorVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();
    }
}
