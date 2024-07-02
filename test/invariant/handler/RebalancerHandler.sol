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

contract RebalancerHandler is Test {
    Actor internal actorUtil;
    Strategy internal strategyUtil;
    EulerAggregationLayer internal eulerAggLayer;
    Rebalancer internal rebalancer;
    WithdrawalQueue internal withdrawalQueue;

    // last function call state
    address currentActor;
    uint256 currentActorIndex;
    bool success;
    bytes returnData;

    constructor(
        EulerAggregationLayer _eulerAggLayer,
        Rebalancer _rebalancer,
        Actor _actor,
        Strategy _strategy,
        WithdrawalQueue _withdrawalQueue
    ) {
        eulerAggLayer = _eulerAggLayer;
        actorUtil = _actor;
        strategyUtil = _strategy;
        rebalancer = _rebalancer;
        withdrawalQueue = _withdrawalQueue;
    }

    function executeRebalance(uint256 _actorIndexSeed) external {
        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (address[] memory strategiesToRebalance,) = withdrawalQueue.getWithdrawalQueueArray();

        (currentActor, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(rebalancer),
            abi.encodeWithSelector(Rebalancer.executeRebalance.selector, address(eulerAggLayer), strategiesToRebalance)
        );
    }
}
