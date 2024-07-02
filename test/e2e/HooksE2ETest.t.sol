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
    IHookTarget,
    ErrorsLib
} from "../common/EulerAggregationLayerBase.t.sol";

contract HooksE2ETest is EulerAggregationLayerBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetHooksConfig() public {
        uint32 expectedHookedFns = eulerAggregationLayer.DEPOSIT() | eulerAggregationLayer.WITHDRAW()
            | eulerAggregationLayer.ADD_STRATEGY() | eulerAggregationLayer.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        eulerAggregationLayer.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

        (address hookTarget, uint32 hookedFns) = eulerAggregationLayer.getHooksConfig();

        assertEq(hookTarget, hooksContract);
        assertEq(hookedFns, expectedHookedFns);
    }

    function testSetHooksConfigWithAddressZero() public {
        uint32 expectedHookedFns = eulerAggregationLayer.DEPOSIT() | eulerAggregationLayer.WITHDRAW()
            | eulerAggregationLayer.ADD_STRATEGY() | eulerAggregationLayer.REMOVE_STRATEGY();

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidHooksTarget.selector);
        eulerAggregationLayer.setHooksConfig(address(0), expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithNotHooksContract() public {
        uint32 expectedHookedFns = eulerAggregationLayer.DEPOSIT() | eulerAggregationLayer.WITHDRAW()
            | eulerAggregationLayer.ADD_STRATEGY() | eulerAggregationLayer.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new NotHooksContract());
        vm.expectRevert(ErrorsLib.NotHooksContract.selector);
        eulerAggregationLayer.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithInvalidHookedFns() public {
        uint32 expectedHookedFns = 1 << 6;
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        vm.expectRevert(ErrorsLib.InvalidHookedFns.selector);
        eulerAggregationLayer.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testHookedDeposit() public {
        uint32 expectedHookedFns = eulerAggregationLayer.DEPOSIT();
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        eulerAggregationLayer.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

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
    }
}

contract HooksContract is IHookTarget {
    function isHookTarget() external pure returns (bytes4) {
        return this.isHookTarget.selector;
    }

    fallback() external payable {}

    receive() external payable {}

    function testToAvoidCoverage() public pure {
        return;
    }
}

contract NotHooksContract is IHookTarget {
    function isHookTarget() external pure returns (bytes4) {
        return 0x0;
    }

    function testToAvoidCoverage() public pure {
        return;
    }
}
