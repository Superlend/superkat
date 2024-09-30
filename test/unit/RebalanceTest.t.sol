// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract RebalanceTest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testRebalanceByDepositing() public {
        uint256 amountToDeposit = 10000e18;

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
        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerEulerEarnVault.totalAllocationPoints();

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
        assertEq(
            (eulerEulerEarnVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + expectedStrategyCash
        );
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanMaxDeposit() public {
        uint256 amountToDeposit = 10000e18;

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
        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerEulerEarnVault.totalAllocationPoints();
        uint256 expectedToDeposit = expectedStrategyCash - strategyBefore.allocated;
        uint256 eTSTMaxDeposit = expectedToDeposit * 7e17 / 1e18;
        // mock max deposit
        vm.mockCall(
            address(eTST), abi.encodeCall(eTST.maxDeposit, (address(eulerEulerEarnVault))), abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        assertEq(eulerEulerEarnVault.totalAllocated(), eTSTMaxDeposit);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), eTSTMaxDeposit);
        assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + eTSTMaxDeposit);
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanCashAvailable() public {
        address[] memory strategiesToRebalance = new address[](1);
        uint256 amountToDeposit = 10000e18;

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

        // rebalance into first strategy
        vm.warp(block.timestamp + 86400);
        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        // create new strategy & add it
        IEVault eTSTsecondary;
        uint256 eTSTsecondaryAllocationPoints = 1500e18;
        {
            eTSTsecondary = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );
            eTSTsecondary.setHookConfig(address(0), 0);
            eTSTsecondary.setInterestRateModel(address(new IRMTestDefault()));
            eTSTsecondary.setMaxLiquidationDiscount(0.2e4);
            eTSTsecondary.setFeeReceiver(feeReceiver);

            _addStrategy(manager, address(eTSTsecondary), eTSTsecondaryAllocationPoints);
        }

        // rebalance into eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTSTsecondary));

            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerEulerEarnVault))),
                strategyBefore.allocated
            );

            uint256 targetCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * eulerEulerEarnVault.getStrategy(address(0)).allocationPoints / eulerEulerEarnVault.totalAllocationPoints();
            uint256 currentCash = eulerEulerEarnVault.totalAssetsAllocatable() - eulerEulerEarnVault.totalAllocated();
            uint256 expectedStrategyCash = currentCash - targetCash;

            vm.prank(user1);
            strategiesToRebalance[0] = address(eTSTsecondary);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            // assertEq(eulerEulerEarnVault.totalAllocated(), eTSTsecondaryMaxDeposit);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerEulerEarnVault))),
                expectedStrategyCash
            );
            assertEq(
                (eulerEulerEarnVault.getStrategy(address(eTSTsecondary))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }
    }

    function testRebalanceByDepositingWhenToDepositIsZero() public {
        uint256 amountToDeposit = 10000e18;

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
        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

        uint256 eTSTMaxDeposit = 0;
        // mock max deposit
        vm.mockCall(
            address(eTST), abi.encodeCall(eTST.maxDeposit, (address(eulerEulerEarnVault))), abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        assertEq(eulerEulerEarnVault.totalAllocated(), strategyBefore.allocated);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);
        assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
    }

    function testRebalanceByWithdrawing() public {
        uint256 amountToDeposit = 10000e18;

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
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerEulerEarnVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerEulerEarnVault.totalAllocationPoints();

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
        assertEq(
            (eulerEulerEarnVault.getStrategy(address(eTST))).allocated,
            strategyBefore.allocated - (strategyBefore.allocated - expectedStrategyCash)
        );
    }

    function testRebalanceByWithdrawingWhenToWithdrawIsGreaterThanMaxWithdraw() public {
        uint256 amountToDeposit = 10000e18;

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
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerEulerEarnVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerEulerEarnVault.totalAllocationPoints();
        uint256 expectedToWithdraw = strategyBefore.allocated - expectedStrategyCash;
        uint256 eTSTMaxWithdraw = expectedToWithdraw * 7e17 / 1e18;
        // mock max withdraw
        vm.mockCall(
            address(eTST), abi.encodeCall(eTST.maxWithdraw, (address(eulerEulerEarnVault))), abi.encode(eTSTMaxWithdraw)
        );

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);

        assertEq(eulerEulerEarnVault.totalAllocated(), strategyBefore.allocated - eTSTMaxWithdraw);
        assertEq(
            eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))),
            strategyBefore.allocated - eTSTMaxWithdraw
        );
        assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated - eTSTMaxWithdraw);
    }
}
