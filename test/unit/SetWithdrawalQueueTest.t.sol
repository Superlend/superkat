// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EulerAggregationLayerBase, EulerAggregationLayer, ErrorsLib} from "../common/EulerAggregationLayerBase.t.sol";

contract SetWithdrawalQueueTest is EulerAggregationLayerBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testSetInvalidWithdrawalQueue() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidPlugin.selector);
        eulerAggregationLayer.setWithdrawalQueue(address(0));
    }

    function testSetWithdrawalQueue() public {
        address newWithdrawalQueue = makeAddr("WITHDRAWAL_QUEUE");

        vm.prank(manager);
        eulerAggregationLayer.setWithdrawalQueue(newWithdrawalQueue);

        assertEq(eulerAggregationLayer.withdrawalQueue(), newWithdrawalQueue);
    }
}
