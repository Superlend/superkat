// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    IWithdrawalQueue,
    IEVault,
    TestERC20
} from "../common/EulerAggregationLayerBase.t.sol";
import {Actor} from "./util/Actor.sol";
import {Strategy} from "./util/Strategy.sol";
import {EulerAggregationLayerHandler} from "./handler/EulerAggregationLayerHandler.sol";
import {RebalancerHandler} from "./handler/RebalancerHandler.sol";
import {WithdrawalQueueHandler} from "./handler/WithdrawalQueueHandler.sol";

contract EulerAggregationLayerInvariants is EulerAggregationLayerBase {
    Actor internal actorUtil;
    Strategy internal strategyUtil;

    EulerAggregationLayerHandler internal eulerAggregationLayerHandler;
    RebalancerHandler internal rebalancerHandler;
    WithdrawalQueueHandler internal withdrawalQueueHandler;

    // other strategies
    IEVault eTSTsecond;
    IEVault eTSTthird;
    IEVault eTSTforth;
    IEVault eTSTfifth;
    IEVault eTSTsixth;

    function setUp() public override {
        super.setUp();

        actorUtil = new Actor();
        actorUtil.includeActor(manager);
        actorUtil.includeActor(deployer);
        actorUtil.includeActor(user1);
        actorUtil.includeActor(user2);

        strategyUtil = new Strategy();
        strategyUtil.includeStrategy(address(eTST));
        _deployOtherStrategies();
        strategyUtil.includeStrategy(address(eTSTsecond));
        strategyUtil.includeStrategy(address(eTSTthird));
        strategyUtil.includeStrategy(address(eTSTforth));
        strategyUtil.includeStrategy(address(eTSTfifth));
        strategyUtil.includeStrategy(address(eTSTsixth));

        eulerAggregationLayerHandler =
            new EulerAggregationLayerHandler(eulerAggregationLayer, actorUtil, strategyUtil, withdrawalQueue);
        rebalancerHandler =
            new RebalancerHandler(eulerAggregationLayer, rebalancer, actorUtil, strategyUtil, withdrawalQueue);
        withdrawalQueueHandler =
            new WithdrawalQueueHandler(eulerAggregationLayer, actorUtil, strategyUtil, withdrawalQueue);

        targetContract(address(eulerAggregationLayerHandler));
        targetContract(address(rebalancerHandler));
        targetContract(address(withdrawalQueueHandler));
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

    function invariant_withdrawalQueue() public view {
        address withdrawalQueueAddr = eulerAggregationLayer.withdrawalQueue();

        (, uint256 withdrawalQueueLength) = IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 cashReserveAllocationPoints = (eulerAggregationLayer.getStrategy(address(0))).allocationPoints;

        if (eulerAggregationLayer.totalAllocationPoints() - cashReserveAllocationPoints == 0) {
            assertEq(withdrawalQueueLength, 0);
        } else {
            assertGt(withdrawalQueueLength, 0);
        }
    }

    function invariant_totalAllocated() public view {
        address withdrawalQueueAddr = eulerAggregationLayer.withdrawalQueue();

        (address[] memory withdrawalQueueArray, uint256 withdrawalQueueLength) =
            IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 aggregatedAllocatedAmount;
        for (uint256 i; i < withdrawalQueueLength; i++) {
            aggregatedAllocatedAmount += (eulerAggregationLayer.getStrategy(withdrawalQueueArray[i])).allocated;
        }

        assertEq(eulerAggregationLayer.totalAllocated(), aggregatedAllocatedAmount);
    }

    function invariant_performanceFee() public view {
        for (uint256 i; i < eulerAggregationLayerHandler.ghostFeeRecipientsLength(); i++) {
            address feeRecipient = eulerAggregationLayerHandler.ghost_feeRecipients(i);

            assertEq(
                assetTST.balanceOf(feeRecipient),
                eulerAggregationLayerHandler.ghost_accumulatedPerformanceFeePerRecipient(feeRecipient)
            );
        }
    }

    function _deployOtherStrategies() private {
        eTSTsecond = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTthird = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTforth = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTfifth = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTsixth = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
    }
}
