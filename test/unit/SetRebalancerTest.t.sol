// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EulerAggregationVaultBase, EulerAggregationVault, ErrorsLib} from "../common/EulerAggregationVaultBase.t.sol";

contract SetRebalancerTest is EulerAggregationVaultBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testSetInvalidRebalancer() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidPlugin.selector);
        eulerAggregationVault.setRebalancer(address(0));
    }

    function testSetRebalancer() public {
        address newRebalancer = makeAddr("Rebalancer");

        vm.prank(manager);
        eulerAggregationVault.setRebalancer(newRebalancer);

        assertEq(eulerAggregationVault.rebalancer(), newRebalancer);
    }
}
