// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationVault,
    ErrorsLib
} from "../common/EulerAggregationVaultBase.t.sol";

contract RebalanceTest is EulerAggregationVaultBase {
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
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationVault.totalAllocationPoints();

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
        assertEq(
            (eulerAggregationVault.getStrategy(address(eTST))).allocated,
            strategyBefore.allocated + expectedStrategyCash
        );
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanMaxDeposit() public {
        uint256 amountToDeposit = 10000e18;

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
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationVault.totalAllocationPoints();
        uint256 expectedToDeposit = expectedStrategyCash - strategyBefore.allocated;
        uint256 eTSTMaxDeposit = expectedToDeposit * 7e17 / 1e18;
        // mock max deposit
        vm.mockCall(
            address(eTST), abi.encodeCall(eTST.maxDeposit, (address(eulerAggregationVault))), abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        assertEq(eulerAggregationVault.totalAllocated(), eTSTMaxDeposit);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), eTSTMaxDeposit);
        assertEq(
            (eulerAggregationVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + eTSTMaxDeposit
        );
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanCashAvailable() public {
        address[] memory strategiesToRebalance = new address[](1);
        uint256 amountToDeposit = 10000e18;

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

        // rebalance into first strategy
        vm.warp(block.timestamp + 86400);
        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        // create new strategy & add it
        IEVault eTSTsecondary;
        uint256 eTSTsecondaryAllocationPoints = 1500e18;
        {
            eTSTsecondary = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );
            _addStrategy(manager, address(eTSTsecondary), eTSTsecondaryAllocationPoints);
        }

        // rebalance into eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationVault.Strategy memory strategyBefore =
                eulerAggregationVault.getStrategy(address(eTSTsecondary));

            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationVault))),
                strategyBefore.allocated
            );

            uint256 targetCash = eulerAggregationVault.totalAssetsAllocatable()
                * eulerAggregationVault.getStrategy(address(0)).allocationPoints
                / eulerAggregationVault.totalAllocationPoints();
            uint256 currentCash =
                eulerAggregationVault.totalAssetsAllocatable() - eulerAggregationVault.totalAllocated();
            uint256 expectedStrategyCash = currentCash - targetCash;

            vm.prank(user1);
            strategiesToRebalance[0] = address(eTSTsecondary);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            // assertEq(eulerAggregationVault.totalAllocated(), eTSTsecondaryMaxDeposit);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationVault))),
                expectedStrategyCash
            );
            assertEq(
                (eulerAggregationVault.getStrategy(address(eTSTsecondary))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }
    }

    function testRebalanceByDepositingWhenToDepositIsZero() public {
        uint256 amountToDeposit = 10000e18;

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
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

        uint256 eTSTMaxDeposit = 0;
        // mock max deposit
        vm.mockCall(
            address(eTST), abi.encodeCall(eTST.maxDeposit, (address(eulerAggregationVault))), abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        assertEq(eulerAggregationVault.totalAllocated(), strategyBefore.allocated);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);
        assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
    }

    function testRebalanceByWithdrawing() public {
        uint256 amountToDeposit = 10000e18;

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
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerAggregationVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationVault.totalAllocationPoints();

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
        assertEq(
            (eulerAggregationVault.getStrategy(address(eTST))).allocated,
            strategyBefore.allocated - (strategyBefore.allocated - expectedStrategyCash)
        );
    }

    function testRebalanceByWithdrawingWhenToWithdrawIsGreaterThanMaxWithdraw() public {
        uint256 amountToDeposit = 10000e18;

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
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerAggregationVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationVault.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationVault.totalAllocationPoints();
        uint256 expectedToWithdraw = strategyBefore.allocated - expectedStrategyCash;
        uint256 eTSTMaxWithdraw = expectedToWithdraw * 7e17 / 1e18;
        // mock max withdraw
        vm.mockCall(
            address(eTST),
            abi.encodeCall(eTST.maxWithdraw, (address(eulerAggregationVault))),
            abi.encode(eTSTMaxWithdraw)
        );

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);

        assertEq(eulerAggregationVault.totalAllocated(), strategyBefore.allocated - eTSTMaxWithdraw);
        assertEq(
            eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))),
            strategyBefore.allocated - eTSTMaxWithdraw
        );
        assertEq(
            (eulerAggregationVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated - eTSTMaxWithdraw
        );
    }
}
