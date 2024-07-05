// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    IEulerAggregationVault
} from "../common/EulerAggregationVaultBase.t.sol";

contract GulpFuzzTest is EulerAggregationVaultBase {
    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testFuzz_interestAccrued_under_uint168(
        uint256 _interestAmount,
        uint256 _depositAmount,
        uint256 _timePassed
    ) public {
        _depositAmount = bound(_depositAmount, 0, type(uint112).max);
        // this makes sure that the mint won't cause overflow in token accounting
        _interestAmount = bound(_interestAmount, 0, type(uint112).max - _depositAmount);
        _timePassed = bound(_timePassed, block.timestamp, type(uint40).max);

        assetTST.mint(user1, _depositAmount);
        vm.startPrank(user1);
        assetTST.approve(address(eulerAggregationVault), _depositAmount);
        eulerAggregationVault.deposit(_depositAmount, user1);
        vm.stopPrank();

        assetTST.mint(address(eulerAggregationVault), _interestAmount);
        eulerAggregationVault.gulp();

        vm.warp(_timePassed);
        uint256 interestAccrued = eulerAggregationVault.interestAccrued();

        assertLe(interestAccrued, type(uint168).max);
    }

    // this tests shows that when you have a very small deposit and a very large interestAmount minted to the contract
    function testFuzz_gulp_under_uint168(uint256 _interestAmount, uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e7, type(uint112).max);
        _interestAmount = bound(_interestAmount, 0, type(uint256).max - _depositAmount); // this makes sure that the mint won't cause overflow

        assetTST.mint(address(eulerAggregationVault), _interestAmount);

        assetTST.mint(user1, _depositAmount);
        vm.startPrank(user1);
        assetTST.approve(address(eulerAggregationVault), _depositAmount);
        eulerAggregationVault.deposit(_depositAmount, user1);
        vm.stopPrank();

        eulerAggregationVault.gulp();

        EulerAggregationVault.AggregationVaultSavingRate memory aggregationVaultSavingRate =
            eulerAggregationVault.getAggregationVaultSavingRate();

        if (_interestAmount <= type(uint168).max) {
            assertEq(aggregationVaultSavingRate.interestLeft, _interestAmount);
        } else {
            assertEq(aggregationVaultSavingRate.interestLeft, type(uint168).max);
        }
    }
}
