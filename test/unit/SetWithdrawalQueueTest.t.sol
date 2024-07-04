// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EulerAggregationVaultBase, EulerAggregationVault, ErrorsLib} from "../common/EulerAggregationVaultBase.t.sol";

contract SetWithdrawalQueueTest is EulerAggregationVaultBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testSetInvalidWithdrawalQueue() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidPlugin.selector);
        eulerAggregationVault.setWithdrawalQueue(address(0));
    }

    function testSetWithdrawalQueue() public {
        address newWithdrawalQueue = makeAddr("WITHDRAWAL_QUEUE");

        vm.prank(manager);
        eulerAggregationVault.setWithdrawalQueue(newWithdrawalQueue);

        assertEq(eulerAggregationVault.withdrawalQueue(), newWithdrawalQueue);
    }
}
