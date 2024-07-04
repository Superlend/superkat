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
    IHookTarget,
    ErrorsLib
} from "../common/EulerAggregationVaultBase.t.sol";

contract HooksE2ETest is EulerAggregationVaultBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetHooksConfig() public {
        uint32 expectedHookedFns = eulerAggregationVault.DEPOSIT() | eulerAggregationVault.WITHDRAW()
            | eulerAggregationVault.ADD_STRATEGY() | eulerAggregationVault.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        eulerAggregationVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

        (address hookTarget, uint32 hookedFns) = eulerAggregationVault.getHooksConfig();

        assertEq(hookTarget, hooksContract);
        assertEq(hookedFns, expectedHookedFns);
    }

    function testSetHooksConfigWithAddressZero() public {
        uint32 expectedHookedFns = eulerAggregationVault.DEPOSIT() | eulerAggregationVault.WITHDRAW()
            | eulerAggregationVault.ADD_STRATEGY() | eulerAggregationVault.REMOVE_STRATEGY();

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidHooksTarget.selector);
        eulerAggregationVault.setHooksConfig(address(0), expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithNotHooksContract() public {
        uint32 expectedHookedFns = eulerAggregationVault.DEPOSIT() | eulerAggregationVault.WITHDRAW()
            | eulerAggregationVault.ADD_STRATEGY() | eulerAggregationVault.REMOVE_STRATEGY();

        vm.startPrank(manager);
        address hooksContract = address(new NotHooksContract());
        vm.expectRevert(ErrorsLib.NotHooksContract.selector);
        eulerAggregationVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithInvalidHookedFns() public {
        uint32 expectedHookedFns = 1 << 6;
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        vm.expectRevert(ErrorsLib.InvalidHookedFns.selector);
        eulerAggregationVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testHookedDeposit() public {
        uint32 expectedHookedFns = eulerAggregationVault.DEPOSIT();
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        eulerAggregationVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

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
