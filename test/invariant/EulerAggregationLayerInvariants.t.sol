// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    IWithdrawalQueue
} from "../common/EulerAggregationLayerBase.t.sol";

contract EulerAggregationLayerInvariants is EulerAggregationLayerBase {
    function setUp() public override {
        super.setUp();

        targetContract(address(eulerAggregationLayer));
    }

    function invariant_totalAllocationPoints() public view {
        address withdrawalQueueAddr = eulerAggregationLayer.withdrawalQueue();

        (address[] memory withdrawalQueueArray, uint256 withdrawalQueueLength) =
            IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 expectedTotalAllocationpoints;
        expectedTotalAllocationpoints += (eulerAggregationLayer.getStrategy(address(0))).allocationPoints;
        for (uint256 i; i < withdrawalQueueLength; i++) {
            expectedTotalAllocationpoints +=
                (eulerAggregationLayer.getStrategy(withdrawalQueueArray[i])).allocationPoints;
        }

        assertEq(eulerAggregationLayer.totalAllocationPoints(), expectedTotalAllocationpoints);
    }
}
