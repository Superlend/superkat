// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract GulpTest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

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

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }
    }

    function testGulpAfterNegativeYieldEqualToInterestLeft() public {
        eulerEulerEarnVault.gulp();
        (,, uint168 interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();
        assertEq(eulerEulerEarnVault.interestAccrued(), 0);
        assertEq(interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerEulerEarnVault.gulp();
        assertEq(eulerEulerEarnVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerEulerEarnVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 earnCurrentStrategyShareBalance = eTST.balanceOf(address(eulerEulerEarnVault));
            uint256 earnCurrentStrategyUnderlyingBalance = eTST.convertToAssets(earnCurrentStrategyShareBalance);
            uint256 earnNewStrategyUnderlyingBalance = earnCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = earnNewStrategyUnderlyingBalance - earnCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerEulerEarnVault));
        }
        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        assertEq(eulerEulerEarnVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerEulerEarnVault.interestAccrued(), 23809523809523809523);
        eulerEulerEarnVault.gulp();
        (,, interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();
        assertEq(interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerEulerEarnVault.gulp();
        (,, interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();

        // mock a decrease of strategy balance by interestLeft
        uint256 earnCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        uint256 earnCurrentStrategyBalanceAfterNegYield = earnCurrentStrategyBalance - interestLeft;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerEulerEarnVault)),
            abi.encode(earnCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerEulerEarnVault.harvest();
    }

    function testGulpAfterNegativeYieldBiggerThanInterestLeft() public {
        eulerEulerEarnVault.gulp();
        (,, uint168 interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();
        assertEq(eulerEulerEarnVault.interestAccrued(), 0);
        assertEq(interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerEulerEarnVault.gulp();
        assertEq(eulerEulerEarnVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerEulerEarnVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 earnCurrentStrategyShareBalance = eTST.balanceOf(address(eulerEulerEarnVault));
            uint256 earnCurrentStrategyUnderlyingBalance = eTST.convertToAssets(earnCurrentStrategyShareBalance);
            uint256 earnNewStrategyUnderlyingBalance = earnCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = earnNewStrategyUnderlyingBalance - earnCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerEulerEarnVault));
        }
        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        assertEq(eulerEulerEarnVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerEulerEarnVault.interestAccrued(), 23809523809523809523);
        eulerEulerEarnVault.gulp();
        (,, interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();
        assertEq(interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerEulerEarnVault.gulp();
        (,, interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();

        // mock a decrease of strategy balance by interestLeft
        uint256 earnCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        uint256 earnCurrentStrategyBalanceAfterNegYield = earnCurrentStrategyBalance - (interestLeft * 2);
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerEulerEarnVault)),
            abi.encode(earnCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerEulerEarnVault.harvest();
    }
}
