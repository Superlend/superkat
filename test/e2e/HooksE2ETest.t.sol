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
            | fourSixTwoSixAgg.REBALANCE() | fourSixTwoSixAgg.ADD_STRATEGY() | fourSixTwoSixAgg.REMOVE_STRATEGY();

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
            | fourSixTwoSixAgg.REBALANCE() | fourSixTwoSixAgg.ADD_STRATEGY() | fourSixTwoSixAgg.REMOVE_STRATEGY();

        vm.startPrank(manager);
        vm.expectRevert(Hooks.InvalidHooksTarget.selector);
        fourSixTwoSixAgg.setHooksConfig(address(0), expectedHookedFns);
        vm.stopPrank();
    }
}

contract HooksContract is IHookTarget {
    function isHookTarget() external returns (bytes4) {
        return this.isHookTarget.selector;
    }
}
