// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Rewards} from "./Rewards.sol";
import {Hooks} from "./Hooks.sol";
import {WithdrawalQueue} from "./WithdrawalQueue.sol";
import {FourSixTwoSixAgg} from "./FourSixTwoSixAgg.sol";

contract FourSixTwoSixAggFactory {
    // core dependencies
    address public immutable evc;
    address public immutable balanceTracker;
    // core modules
    address public immutable rewardsImpl;
    address public immutable hooksImpl;
    // peripheries
    /// @dev Rebalancer periphery, one instance can serve different aggregation vaults
    address public immutable rebalancer;
    /// @dev Withdrawal queue perihperhy, need to be deployed per aggregation vault
    address public immutable withdrawalQueueImpl;

    constructor(
        address _evc,
        address _balanceTracker,
        address _rewardsImpl,
        address _hooksImpl,
        address _rebalancer,
        address _withdrawalQueueImpl
    ) {
        evc = _evc;
        balanceTracker = _balanceTracker;
        rewardsImpl = _rewardsImpl;
        hooksImpl = _hooksImpl;

        rebalancer = _rebalancer;
        withdrawalQueueImpl = _withdrawalQueueImpl;
    }

    // TODO: decrease bytecode size, use clones or something
    function deployEulerAggregationLayer(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external returns (address) {
        // cloning core modules
        address rewardsImplAddr = Clones.clone(rewardsImpl);
        Hooks hooks = Hooks(Clones.clone(hooksImpl));

        // cloning peripheries
        WithdrawalQueue withdrawalQueue = WithdrawalQueue(Clones.clone(withdrawalQueueImpl));

        // deploy new aggregation vault
        FourSixTwoSixAgg fourSixTwoSixAgg = new FourSixTwoSixAgg(rewardsImplAddr, address(hooks));

        withdrawalQueue.init(msg.sender, address(fourSixTwoSixAgg));
        fourSixTwoSixAgg.init(
            evc,
            balanceTracker,
            address(withdrawalQueue),
            rebalancer,
            msg.sender,
            _asset,
            _name,
            _symbol,
            _initialCashAllocationPoints
        );

        return address(fourSixTwoSixAgg);
    }
}
