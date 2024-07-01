// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EulerAggregationLayerBase, EulerAggregationLayer, ErrorsLib} from "../common/EulerAggregationLayerBase.t.sol";

contract SetRebalancerTest is EulerAggregationLayerBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testSetInvalidRebalancer() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidPlugin.selector);
        eulerAggregationLayer.setRebalancer(address(0));
    }

    function testSetRebalancer() public {
        address newRebalancer = makeAddr("Rebalancer");

        vm.prank(manager);
        eulerAggregationLayer.setRebalancer(newRebalancer);

        assertEq(eulerAggregationLayer.rebalancer(), newRebalancer);
    }
}
