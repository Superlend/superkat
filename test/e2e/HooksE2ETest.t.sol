// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract HooksE2ETest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetHooksConfig() public {
        uint32 expectedHookedFns =
            ConstantsLib.DEPOSIT | ConstantsLib.WITHDRAW | ConstantsLib.ADD_STRATEGY | ConstantsLib.REMOVE_STRATEGY;

        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        eulerEulerEarnVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

        (address hookTarget, uint32 hookedFns) = eulerEulerEarnVault.getHooksConfig();

        assertEq(hookTarget, hooksContract);
        assertEq(hookedFns, expectedHookedFns);
    }

    function testSetHooksConfigWithAddressZero() public {
        uint32 expectedHookedFns =
            ConstantsLib.DEPOSIT | ConstantsLib.WITHDRAW | ConstantsLib.ADD_STRATEGY | ConstantsLib.REMOVE_STRATEGY;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidHooksTarget.selector);
        eulerEulerEarnVault.setHooksConfig(address(0), expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithNotHooksContract() public {
        uint32 expectedHookedFns =
            ConstantsLib.DEPOSIT | ConstantsLib.WITHDRAW | ConstantsLib.ADD_STRATEGY | ConstantsLib.REMOVE_STRATEGY;

        vm.startPrank(manager);
        address hooksContract = address(new NotHooksContract());
        vm.expectRevert(ErrorsLib.NotHooksContract.selector);
        eulerEulerEarnVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testSetHooksConfigWithInvalidHookedFns() public {
        uint32 expectedHookedFns = 1 << 6;
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        vm.expectRevert(ErrorsLib.InvalidHookedFns.selector);
        eulerEulerEarnVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();
    }

    function testHookedDeposit() public {
        uint32 expectedHookedFns = ConstantsLib.DEPOSIT;
        vm.startPrank(manager);
        address hooksContract = address(new HooksContract());
        eulerEulerEarnVault.setHooksConfig(hooksContract, expectedHookedFns);
        vm.stopPrank();

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
