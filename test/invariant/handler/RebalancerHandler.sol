// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    Test,
    EulerAggregationVaultBase,
    EulerAggregationVault,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationVault,
    ErrorsLib,
    IERC4626,
    Rebalancer,
    WithdrawalQueue
} from "../../common/EulerAggregationVaultBase.t.sol";
import {Actor} from "../util/Actor.sol";
import {Strategy} from "../util/Strategy.sol";

contract RebalancerHandler is Test {
    Actor internal actorUtil;
    Strategy internal strategyUtil;
    EulerAggregationVault internal eulerAggVault;
    Rebalancer internal rebalancer;
    WithdrawalQueue internal withdrawalQueue;

    // last function call state
    address currentActor;
    uint256 currentActorIndex;
    bool success;
    bytes returnData;

    constructor(
        EulerAggregationVault _eulerAggVault,
        Rebalancer _rebalancer,
        Actor _actor,
        Strategy _strategy,
        WithdrawalQueue _withdrawalQueue
    ) {
        eulerAggVault = _eulerAggVault;
        actorUtil = _actor;
        strategyUtil = _strategy;
        rebalancer = _rebalancer;
        withdrawalQueue = _withdrawalQueue;
    }

    function executeRebalance(uint256 _actorIndexSeed) external {
        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (address[] memory strategiesToRebalance, uint256 strategiesCounter) = withdrawalQueue.getWithdrawalQueueArray();
        (currentActor, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(rebalancer),
            abi.encodeWithSelector(Rebalancer.executeRebalance.selector, address(eulerAggVault), strategiesToRebalance)
        );

        for (uint256 i; i < strategiesCounter; i++) {
            assertEq(
                IERC4626(strategiesToRebalance[i]).maxWithdraw(address(eulerAggVault)),
                (eulerAggVault.getStrategy(strategiesToRebalance[i])).allocated
            );
        }
    }
}
