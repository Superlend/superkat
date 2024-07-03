// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    Test,
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationLayer,
    ErrorsLib,
    IERC4626,
    Rebalancer,
    WithdrawalQueue
} from "../../common/EulerAggregationLayerBase.t.sol";
import {Actor} from "../util/Actor.sol";
import {Strategy} from "../util/Strategy.sol";

contract WithdrawalQueueHandler is Test {
    Actor internal actorUtil;
    Strategy internal strategyUtil;
    EulerAggregationLayer internal eulerAggLayer;
    WithdrawalQueue internal withdrawalQueue;

    // last function call state
    address currentActor;
    uint256 currentActorIndex;
    bool success;
    bytes returnData;

    constructor(
        EulerAggregationLayer _eulerAggLayer,
        Actor _actor,
        Strategy _strategy,
        WithdrawalQueue _withdrawalQueue
    ) {
        eulerAggLayer = _eulerAggLayer;
        actorUtil = _actor;
        strategyUtil = _strategy;
        withdrawalQueue = _withdrawalQueue;
    }

    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) external {
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(withdrawalQueue),
            abi.encodeWithSelector(WithdrawalQueue.reorderWithdrawalQueue.selector, _index1, _index2)
        );
    }
}
