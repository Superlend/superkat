// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEulerAggregationVault
} from "../common/EulerAggregationVaultBase.t.sol";

contract GulpTest is EulerAggregationVaultBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationVault), amountToDeposit);
            eulerAggregationVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }
    }

    function testGulpAfterNegativeYieldEqualToInterestLeft() public {
        eulerAggregationVault.gulp();
        (,, uint168 interestLeft) = eulerAggregationVault.getAggregationVaultSavingRate();
        assertEq(eulerAggregationVault.interestAccrued(), 0);
        assertEq(interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerAggregationVault.gulp();
        assertEq(eulerAggregationVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerAggregationVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerAggregationVault));
        }
        vm.prank(user1);
        eulerAggregationVault.harvest();

        assertEq(eulerAggregationVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerAggregationVault.interestAccrued(), 23809523809523809523);
        eulerAggregationVault.gulp();
        (,, interestLeft) = eulerAggregationVault.getAggregationVaultSavingRate();
        assertEq(interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerAggregationVault.gulp();
        (,, interestLeft) = eulerAggregationVault.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - interestLeft;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerAggregationVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerAggregationVault.harvest();
    }

    function testGulpAfterNegativeYieldBiggerThanInterestLeft() public {
        eulerAggregationVault.gulp();
        (,, uint168 interestLeft) = eulerAggregationVault.getAggregationVaultSavingRate();
        assertEq(eulerAggregationVault.interestAccrued(), 0);
        assertEq(interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerAggregationVault.gulp();
        assertEq(eulerAggregationVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerAggregationVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerAggregationVault));
        }
        vm.prank(user1);
        eulerAggregationVault.harvest();

        assertEq(eulerAggregationVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerAggregationVault.interestAccrued(), 23809523809523809523);
        eulerAggregationVault.gulp();
        (,, interestLeft) = eulerAggregationVault.getAggregationVaultSavingRate();
        assertEq(interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerAggregationVault.gulp();
        (,, interestLeft) = eulerAggregationVault.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - (interestLeft * 2);
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerAggregationVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerAggregationVault.harvest();
    }
}
