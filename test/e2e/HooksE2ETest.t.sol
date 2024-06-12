// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    FourSixTwoSixAggBase,
    FourSixTwoSixAgg,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IHookTarget,
    Hooks
} from "../common/FourSixTwoSixAggBase.t.sol";

contract HooksE2ETest is FourSixTwoSixAggBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetHooksConfig() public {
        uint32 expectedHookedFns = fourSixTwoSixAgg.DEPOSIT() | fourSixTwoSixAgg.WITHDRAW()
            | fourSixTwoSixAgg.ADD_STRATEGY() | fourSixTwoSixAgg.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        fourSixTwoSixAgg.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

        (address hookTarget, uint32 hookedFns) = fourSixTwoSixAgg.getHooksConfig();

        assertEq(hookTarget, hooksContract);
        assertEq(hookedFns, expectedHookedFns);
    }

    function testSetHooksConfigWithAddressZero() public {
        uint32 expectedHookedFns = fourSixTwoSixAgg.DEPOSIT() | fourSixTwoSixAgg.WITHDRAW()
            | fourSixTwoSixAgg.ADD_STRATEGY() | fourSixTwoSixAgg.REMOVE_STRATEGY();

        vm.startPrank(manager);
        vm.expectRevert(Hooks.InvalidHooksTarget.selector);
        fourSixTwoSixAgg.setHooksConfig(address(0), expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithNotHooksContract() public {
        uint32 expectedHookedFns = fourSixTwoSixAgg.DEPOSIT() | fourSixTwoSixAgg.WITHDRAW()
            | fourSixTwoSixAgg.ADD_STRATEGY() | fourSixTwoSixAgg.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new NotHooksContract());
        vm.expectRevert(Hooks.NotHooksContract.selector);
        fourSixTwoSixAgg.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithInvalidHookedFns() public {
        uint32 expectedHookedFns = 1 << 5;
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        vm.expectRevert(Hooks.InvalidHookedFns.selector);
        fourSixTwoSixAgg.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testHookedDeposit() public {
        uint32 expectedHookedFns = fourSixTwoSixAgg.DEPOSIT();
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        fourSixTwoSixAgg.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;
        // deposit into aggregator
        {
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }
    }
}

contract HooksContract is IHookTarget {
    function isHookTarget() external pure returns (bytes4) {
        return this.isHookTarget.selector;
    }

    fallback() external payable {}
}

contract NotHooksContract is IHookTarget {
    function isHookTarget() external pure returns (bytes4) {
        return 0x0;
    }
}
