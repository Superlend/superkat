// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    IWithdrawalQueue,
    IEVault,
    TestERC20
} from "../common/EulerAggregationVaultBase.t.sol";
import {Actor} from "./util/Actor.sol";
import {Strategy} from "./util/Strategy.sol";
import {EulerAggregationVaultHandler} from "./handler/EulerAggregationVaultHandler.sol";
import {RebalancerHandler} from "./handler/RebalancerHandler.sol";
import {WithdrawalQueueHandler} from "./handler/WithdrawalQueueHandler.sol";

contract EulerAggregationVaultInvariants is EulerAggregationVaultBase {
    Actor internal actorUtil;
    Strategy internal strategyUtil;

    EulerAggregationVaultHandler internal eulerAggregationVaultHandler;
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

        eulerAggregationVaultHandler =
            new EulerAggregationVaultHandler(eulerAggregationVault, actorUtil, strategyUtil, withdrawalQueue);
        rebalancerHandler =
            new RebalancerHandler(eulerAggregationVault, rebalancer, actorUtil, strategyUtil, withdrawalQueue);
        withdrawalQueueHandler =
            new WithdrawalQueueHandler(eulerAggregationVault, actorUtil, strategyUtil, withdrawalQueue);

        targetContract(address(eulerAggregationVaultHandler));
        targetContract(address(rebalancerHandler));
        targetContract(address(withdrawalQueueHandler));
    }

    function invariant_gulp() public {
        eulerAggregationVault.gulp();

        assertEq(
            eulerAggregationVault.totalAssetsAllocatable(),
            eulerAggregationVault.totalAssetsDeposited()
                + (eulerAggregationVault.getAggregationVaultSavingRate()).interestLeft
        );
    }

    function invariant_totalAllocationPoints() public view {
        address withdrawalQueueAddr = eulerAggregationVault.withdrawalQueue();

        (address[] memory withdrawalQueueArray, uint256 withdrawalQueueLength) =
            IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 expectedTotalAllocationpoints;
        expectedTotalAllocationpoints += (eulerAggregationVault.getStrategy(address(0))).allocationPoints;
        for (uint256 i; i < withdrawalQueueLength; i++) {
            expectedTotalAllocationpoints +=
                (eulerAggregationVault.getStrategy(withdrawalQueueArray[i])).allocationPoints;
        }

        assertEq(eulerAggregationVault.totalAllocationPoints(), expectedTotalAllocationpoints);
    }

    function invariant_withdrawalQueue() public view {
        address withdrawalQueueAddr = eulerAggregationVault.withdrawalQueue();

        (, uint256 withdrawalQueueLength) = IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 cashReserveAllocationPoints = (eulerAggregationVault.getStrategy(address(0))).allocationPoints;

        if (eulerAggregationVault.totalAllocationPoints() - cashReserveAllocationPoints == 0) {
            assertEq(withdrawalQueueLength, 0);
        } else {
            assertGt(withdrawalQueueLength, 0);
        }
    }

    function invariant_totalAllocated() public view {
        address withdrawalQueueAddr = eulerAggregationVault.withdrawalQueue();

        (address[] memory withdrawalQueueArray, uint256 withdrawalQueueLength) =
            IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 aggregatedAllocatedAmount;
        for (uint256 i; i < withdrawalQueueLength; i++) {
            aggregatedAllocatedAmount += (eulerAggregationVault.getStrategy(withdrawalQueueArray[i])).allocated;
        }

        assertEq(eulerAggregationVault.totalAllocated(), aggregatedAllocatedAmount);
    }

    function invariant_performanceFee() public view {
        for (uint256 i; i < eulerAggregationVaultHandler.ghostFeeRecipientsLength(); i++) {
            address feeRecipient = eulerAggregationVaultHandler.ghost_feeRecipients(i);

            assertEq(
                assetTST.balanceOf(feeRecipient),
                eulerAggregationVaultHandler.ghost_accumulatedPerformanceFeePerRecipient(feeRecipient)
            );
        }
    }

    function invariant_interestLeft() public view {
        EulerAggregationVault.AggregationVaultSavingRate memory aggregationVaultSavingRate =
            eulerAggregationVault.getAggregationVaultSavingRate();
        uint256 accruedInterest = eulerAggregationVault.interestAccrued();
        assertGe(aggregationVaultSavingRate.interestLeft, accruedInterest);
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
