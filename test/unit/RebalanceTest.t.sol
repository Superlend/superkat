// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract RebalanceTest is YieldAggregatorBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testRebalanceByDepositing() public {
        uint256 amountToDeposit = 10000e18;

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
        assertEq(
            (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated,
            strategyBefore.allocated + expectedStrategyCash
        );
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanMaxDeposit() public {
        uint256 amountToDeposit = 10000e18;

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
        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
            * strategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();
        uint256 expectedToDeposit = expectedStrategyCash - strategyBefore.allocated;
        uint256 eTSTMaxDeposit = expectedToDeposit * 7e17 / 1e18;
        // mock max deposit
        vm.mockCall(
            address(eTST),
            abi.encodeCall(eTST.maxDeposit, (address(eulerYieldAggregatorVault))),
            abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

        assertEq(eulerYieldAggregatorVault.totalAllocated(), eTSTMaxDeposit);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), eTSTMaxDeposit);
        assertEq(
            (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + eTSTMaxDeposit
        );
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanCashAvailable() public {
        address[] memory strategiesToRebalance = new address[](1);
        uint256 amountToDeposit = 10000e18;

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

        // rebalance into first strategy
        vm.warp(block.timestamp + 86400);
        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

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
            IYieldAggregator.Strategy memory strategyBefore =
                eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary));

            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault))),
                strategyBefore.allocated
            );

            uint256 targetCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * eulerYieldAggregatorVault.getStrategy(address(0)).allocationPoints
                / eulerYieldAggregatorVault.totalAllocationPoints();
            uint256 currentCash =
                eulerYieldAggregatorVault.totalAssetsAllocatable() - eulerYieldAggregatorVault.totalAllocated();
            uint256 expectedStrategyCash = currentCash - targetCash;

            vm.prank(user1);
            strategiesToRebalance[0] = address(eTSTsecondary);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            // assertEq(eulerYieldAggregatorVault.totalAllocated(), eTSTsecondaryMaxDeposit);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault))),
                expectedStrategyCash
            );
            assertEq(
                (eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }
    }

    function testRebalanceByDepositingWhenToDepositIsZero() public {
        uint256 amountToDeposit = 10000e18;

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
        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

        uint256 eTSTMaxDeposit = 0;
        // mock max deposit
        vm.mockCall(
            address(eTST),
            abi.encodeCall(eTST.maxDeposit, (address(eulerYieldAggregatorVault))),
            abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

        assertEq(eulerYieldAggregatorVault.totalAllocated(), strategyBefore.allocated);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);
        assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
    }

    function testRebalanceByWithdrawing() public {
        uint256 amountToDeposit = 10000e18;

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
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerYieldAggregatorVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
            * strategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

        assertEq(eulerYieldAggregatorVault.totalAllocated(), expectedStrategyCash);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedStrategyCash);
        assertEq(
            (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated,
            strategyBefore.allocated - (strategyBefore.allocated - expectedStrategyCash)
        );
    }

    function testRebalanceByWithdrawingWhenToWithdrawIsGreaterThanMaxWithdraw() public {
        uint256 amountToDeposit = 10000e18;

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
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerYieldAggregatorVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
            * strategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();
        uint256 expectedToWithdraw = strategyBefore.allocated - expectedStrategyCash;
        uint256 eTSTMaxWithdraw = expectedToWithdraw * 7e17 / 1e18;
        // mock max withdraw
        vm.mockCall(
            address(eTST),
            abi.encodeCall(eTST.maxWithdraw, (address(eulerYieldAggregatorVault))),
            abi.encode(eTSTMaxWithdraw)
        );

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

        assertEq(eulerYieldAggregatorVault.totalAllocated(), strategyBefore.allocated - eTSTMaxWithdraw);
        assertEq(
            eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))),
            strategyBefore.allocated - eTSTMaxWithdraw
        );
        assertEq(
            (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated - eTSTMaxWithdraw
        );
    }
}
