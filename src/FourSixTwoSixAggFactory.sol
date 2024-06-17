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
        uint256 _initialCashAllocationPoints
    ) external returns (address) {
        WithdrawalQueue withdrawalQueue = new WithdrawalQueue();
        FourSixTwoSixAgg fourSixTwoSixAgg = new FourSixTwoSixAgg();

        address owner = msg.sender;

        withdrawalQueue.init(owner, address(fourSixTwoSixAgg));
        fourSixTwoSixAgg.init(
            evc,
            balanceTracker,
            address(withdrawalQueue),
            rebalancer,
            owner,
            _asset,
            _name,
            _symbol,
            _initialCashAllocationPoints
        );

        return address(fourSixTwoSixAgg);
    }
}
