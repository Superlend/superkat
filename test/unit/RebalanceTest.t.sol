// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationLayer
} from "../common/EulerAggregationLayerBase.t.sol";

contract RebalanceTest is EulerAggregationLayerBase {
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
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationLayer.totalAllocationPoints();

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

        assertEq(eulerAggregationLayer.totalAllocated(), expectedStrategyCash);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedStrategyCash);
        assertEq(
            (eulerAggregationLayer.getStrategy(address(eTST))).allocated,
            strategyBefore.allocated + expectedStrategyCash
        );
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanMaxDeposit() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationLayer.totalAllocationPoints();
        uint256 expectedToDeposit = expectedStrategyCash - strategyBefore.allocated;
        uint256 eTSTMaxDeposit = expectedToDeposit * 7e17 / 1e18;
        // mock max deposit
        vm.mockCall(
            address(eTST), abi.encodeCall(eTST.maxDeposit, (address(eulerAggregationLayer))), abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

        assertEq(eulerAggregationLayer.totalAllocated(), eTSTMaxDeposit);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), eTSTMaxDeposit);
        assertEq(
            (eulerAggregationLayer.getStrategy(address(eTST))).allocated, strategyBefore.allocated + eTSTMaxDeposit
        );
    }

    function testRebalanceByDepositingWhenToDepositIsGreaterThanCashAvailable() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into first strategy
        vm.warp(block.timestamp + 86400);
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

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
            IEulerAggregationLayer.Strategy memory strategyBefore =
                eulerAggregationLayer.getStrategy(address(eTSTsecondary));

            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                strategyBefore.allocated
            );

            uint256 targetCash = eulerAggregationLayer.totalAssetsAllocatable()
                * eulerAggregationLayer.getStrategy(address(0)).allocationPoints
                / eulerAggregationLayer.totalAllocationPoints();
            uint256 currentCash =
                eulerAggregationLayer.totalAssetsAllocatable() - eulerAggregationLayer.totalAllocated();
            uint256 expectedStrategyCash = currentCash - targetCash;

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTSTsecondary);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            // assertEq(eulerAggregationLayer.totalAllocated(), eTSTsecondaryMaxDeposit);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                expectedStrategyCash
            );
            assertEq(
                (eulerAggregationLayer.getStrategy(address(eTSTsecondary))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }
    }

    function testRebalanceByDepositingWhenToDepositIsZero() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

        uint256 eTSTMaxDeposit = 0;
        // mock max deposit
        vm.mockCall(
            address(eTST), abi.encodeCall(eTST.maxDeposit, (address(eulerAggregationLayer))), abi.encode(eTSTMaxDeposit)
        );

        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

        assertEq(eulerAggregationLayer.totalAllocated(), strategyBefore.allocated);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);
        assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
    }

    function testRebalanceByWithdrawing() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerAggregationLayer.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationLayer.totalAllocationPoints();

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

        assertEq(eulerAggregationLayer.totalAllocated(), expectedStrategyCash);
        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedStrategyCash);
        assertEq(
            (eulerAggregationLayer.getStrategy(address(eTST))).allocated,
            strategyBefore.allocated - (strategyBefore.allocated - expectedStrategyCash)
        );
    }

    function testRebalanceByWithdrawingWhenToWithdrawIsGreaterThanMaxWithdraw() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        vm.prank(user1);
        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

        // decrease allocation points
        uint256 newAllocationPoints = 300e18;
        vm.prank(manager);
        eulerAggregationLayer.adjustAllocationPoints(address(eTST), newAllocationPoints);

        vm.warp(block.timestamp + 86400);

        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

        assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

        uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable() * strategyBefore.allocationPoints
            / eulerAggregationLayer.totalAllocationPoints();
        uint256 expectedToWithdraw = strategyBefore.allocated - expectedStrategyCash;
        uint256 eTSTMaxWithdraw = expectedToWithdraw * 7e17 / 1e18;
        // mock max withdraw
        vm.mockCall(
            address(eTST),
            abi.encodeCall(eTST.maxWithdraw, (address(eulerAggregationLayer))),
            abi.encode(eTSTMaxWithdraw)
        );

        vm.prank(user1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

        // assertEq(eulerAggregationLayer.totalAllocated(), strategyBefore.allocated - eTSTMaxWithdraw);
        // assertEq(
        //     eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated - eTSTMaxWithdraw
        // );
        // assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, strategyBefore.allocated - eTSTMaxWithdraw);
    }
}
