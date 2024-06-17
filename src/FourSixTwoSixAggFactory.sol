// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FourSixTwoSixAgg} from "./FourSixTwoSixAgg.sol";
import {WithdrawalQueue} from "./WithdrawalQueue.sol";

contract FourSixTwoSixAggFactory {
    address public immutable evc;
    address public immutable balanceTracker;
    address public immutable rebalancer;

    constructor(address _evc, address _balanceTracker, address _rebalancer) {
        evc = _evc;
        balanceTracker = _balanceTracker;
        rebalancer = _rebalancer;
    }

    // TODO: decrease bytecode size, use clones or something
    function deployEulerAggregationLayer(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints,
        address[] memory _initialStrategies,
        uint256[] memory _initialStrategiesAllocationPoints
    ) external returns (address) {
        address withdrawalQueueAddr = address(new WithdrawalQueue());
        FourSixTwoSixAgg fourSixTwoSixAggAddr = new FourSixTwoSixAgg();

        fourSixTwoSixAggAddr.init(
            evc,
            balanceTracker,
            withdrawalQueueAddr,
            rebalancer,
            msg.sender,
            _asset,
            _name,
            _symbol,
            _initialCashAllocationPoints,
            _initialStrategies,
            _initialStrategiesAllocationPoints
        );

        return address(fourSixTwoSixAggAddr);
    }
}
