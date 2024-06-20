// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IHookTarget,
    ErrorsLib
} from "../common/AggregationLayerVaultBase.t.sol";

contract HooksE2ETest is AggregationLayerVaultBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetHooksConfig() public {
        uint32 expectedHookedFns = aggregationLayerVault.DEPOSIT() | aggregationLayerVault.WITHDRAW()
            | aggregationLayerVault.ADD_STRATEGY() | aggregationLayerVault.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        aggregationLayerVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

        (address hookTarget, uint32 hookedFns) = aggregationLayerVault.getHooksConfig();

        assertEq(hookTarget, hooksContract);
        assertEq(hookedFns, expectedHookedFns);
    }

    function testSetHooksConfigWithAddressZero() public {
        uint32 expectedHookedFns = aggregationLayerVault.DEPOSIT() | aggregationLayerVault.WITHDRAW()
            | aggregationLayerVault.ADD_STRATEGY() | aggregationLayerVault.REMOVE_STRATEGY();

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidHooksTarget.selector);
        aggregationLayerVault.setHooksConfig(address(0), expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithNotHooksContract() public {
        uint32 expectedHookedFns = aggregationLayerVault.DEPOSIT() | aggregationLayerVault.WITHDRAW()
            | aggregationLayerVault.ADD_STRATEGY() | aggregationLayerVault.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new NotHooksContract());
        vm.expectRevert(ErrorsLib.NotHooksContract.selector);
        aggregationLayerVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithInvalidHookedFns() public {
        uint32 expectedHookedFns = 1 << 6;
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        vm.expectRevert(ErrorsLib.InvalidHookedFns.selector);
        aggregationLayerVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testHookedDeposit() public {
        uint32 expectedHookedFns = aggregationLayerVault.DEPOSIT();
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        aggregationLayerVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;
        // deposit into aggregator
        {
            uint256 balanceBefore = aggregationLayerVault.balanceOf(user1);
            uint256 totalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(aggregationLayerVault), amountToDeposit);
            aggregationLayerVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(aggregationLayerVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(aggregationLayerVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
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
