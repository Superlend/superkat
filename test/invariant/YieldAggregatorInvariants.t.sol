// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    YieldAggregatorBase,
    YieldAggregator,
    IEVault,
    TestERC20,
    IYieldAggregator,
    AggAmountCap,
    IRMTestDefault,
    ConstantsLib
} from "../common/YieldAggregatorBase.t.sol";
import {Actor} from "./util/Actor.sol";
import {Strategy} from "./util/Strategy.sol";
import {YieldAggregatorHandler} from "./handler/YieldAggregatorHandler.sol";

contract YieldAggregatorInvariants is YieldAggregatorBase {
    Actor internal actorUtil;
    Strategy internal strategyUtil;

    YieldAggregatorHandler internal eulerYieldAggregatorVaultHandler;

    // other strategies
    IEVault eTSTsecond;
    IEVault eTSTthird;
    IEVault eTSTforth;
    IEVault eTSTfifth;
    IEVault eTSTsixth;

    function setUp() public override {
        super.setUp();

        actorUtil = new Actor(address(eulerYieldAggregatorVault));
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
        // cash reserve strategy
        strategyUtil.includeStrategy(address(0));

        eulerYieldAggregatorVaultHandler =
            new YieldAggregatorHandler(eulerYieldAggregatorVault, actorUtil, strategyUtil);

        targetContract(address(eulerYieldAggregatorVaultHandler));
    }

    // Right after gulp, total assets allocatable should be always equal to total assets deposited + interest left.
    function invariant_gulp() public {
        eulerYieldAggregatorVault.gulp();

        if (eulerYieldAggregatorVault.totalSupply() >= ConstantsLib.MIN_SHARES_FOR_GULP) {
            (,, uint168 interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();
            assertEq(
                eulerYieldAggregatorVault.totalAssetsAllocatable(),
                eulerYieldAggregatorVault.totalAssetsDeposited() + interestLeft
            );
        }
    }

    // totalAssetsDeposited should be equal to the totalAssetsAllocatable after SMEAR has passed.
    function invariant_totalAssets() public {
        eulerYieldAggregatorVault.gulp();
        skip(ConstantsLib.INTEREST_SMEAR); // make sure smear has passed
        eulerYieldAggregatorVault.updateInterestAccrued();

        if (eulerYieldAggregatorVault.totalSupply() >= ConstantsLib.MIN_SHARES_FOR_GULP) {
            assertEq(eulerYieldAggregatorVault.totalAssets(), eulerYieldAggregatorVault.totalAssetsAllocatable());
        }
    }

    // total allocation points should be equal to the sum of the allocation points of all strategies.
    function invariant_totalAllocationPoints() public view {
        address[] memory withdrawalQueueArray = eulerYieldAggregatorVault.withdrawalQueue();

        uint256 expectedTotalAllocationpoints;
        expectedTotalAllocationpoints += (eulerYieldAggregatorVault.getStrategy(address(0))).allocationPoints;
        for (uint256 i; i < withdrawalQueueArray.length; i++) {
            IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(withdrawalQueueArray[i]);

            if (strategy.status == IYieldAggregator.StrategyStatus.Active) {
                expectedTotalAllocationpoints += strategy.allocationPoints;
            }
        }

        assertEq(eulerYieldAggregatorVault.totalAllocationPoints(), expectedTotalAllocationpoints);
    }

    // (1) If withdrawal queue length == 0, then the total allocation points should be equal cash reserve allocation points.
    // (2) If length > 0 and the total allocation points == cash reserve allocation points, then every strategy should have a 0 allocation points or should be a strategy in EMERGENCY mode.
    // (3) withdrawal queue length should always be equal the ghost length variable.
    function invariant_withdrawalQueue() public view {
        (address[] memory withdrawalQueueArray) = eulerYieldAggregatorVault.withdrawalQueue();

        uint256 cashReserveAllocationPoints = (eulerYieldAggregatorVault.getStrategy(address(0))).allocationPoints;

        if (withdrawalQueueArray.length == 0) {
            assertEq(eulerYieldAggregatorVault.totalAllocationPoints(), cashReserveAllocationPoints);
        }

        if (
            withdrawalQueueArray.length > 0
                && eulerYieldAggregatorVault.totalAllocationPoints() == cashReserveAllocationPoints
        ) {
            for (uint256 i; i < withdrawalQueueArray.length; i++) {
                IYieldAggregator.Strategy memory strategy =
                    eulerYieldAggregatorVault.getStrategy(withdrawalQueueArray[i]);
                assertEq(
                    strategy.allocationPoints == 0 || strategy.status == IYieldAggregator.StrategyStatus.Emergency, true
                );
            }
        }

        assertEq(withdrawalQueueArray.length, eulerYieldAggregatorVaultHandler.ghost_withdrawalQueueLength());
    }

    // total allocated amount should always be equal the sum of allocated amount in all the strategies.
    function invariant_totalAllocated() public view {
        (address[] memory withdrawalQueueArray) = eulerYieldAggregatorVault.withdrawalQueue();

        uint256 aggregatedAllocatedAmount;
        for (uint256 i; i < withdrawalQueueArray.length; i++) {
            IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(withdrawalQueueArray[i]);

            if (strategy.status == IYieldAggregator.StrategyStatus.Active) {
                aggregatedAllocatedAmount += strategy.allocated;
            }
        }

        assertEq(eulerYieldAggregatorVault.totalAllocated(), aggregatedAllocatedAmount);
    }

    // Balance of a certain fee recipient should always be equal to the ghost tracking variable.
    function invariant_performanceFee() public view {
        for (uint256 i; i < eulerYieldAggregatorVaultHandler.ghostFeeRecipientsLength(); i++) {
            address feeRecipient = eulerYieldAggregatorVaultHandler.ghost_feeRecipients(i);

            assertEq(
                eulerYieldAggregatorVault.balanceOf(feeRecipient),
                eulerYieldAggregatorVaultHandler.ghost_accumulatedPerformanceFeePerRecipient(feeRecipient)
            );
        }
    }

    // the interest left should always be greater or equal current interest accrued value.
    function invariant_interestLeft() public view {
        (,, uint168 interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();
        uint256 accruedInterest = eulerYieldAggregatorVault.interestAccrued();
        assertGe(interestLeft, accruedInterest);
    }

    function invariant_cashReserveStrategyCap() public view {
        assertEq(AggAmountCap.unwrap(eulerYieldAggregatorVault.getStrategy(address(0)).cap), 0);
    }

    function invariant_votingPower() public view {
        address[] memory actorsList = actorUtil.getActors();

        for (uint256 i; i < actorsList.length; i++) {
            assertEq(
                eulerYieldAggregatorVault.balanceOf(actorsList[i]), eulerYieldAggregatorVault.getVotes(actorsList[i])
            );
        }
    }

    function _deployOtherStrategies() private {
        eTSTsecond = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTsecond.setHookConfig(address(0), 0);
        eTSTsecond.setInterestRateModel(address(new IRMTestDefault()));
        eTSTsecond.setMaxLiquidationDiscount(0.2e4);
        eTSTsecond.setFeeReceiver(feeReceiver);

        eTSTthird = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTthird.setHookConfig(address(0), 0);
        eTSTthird.setInterestRateModel(address(new IRMTestDefault()));
        eTSTthird.setMaxLiquidationDiscount(0.2e4);
        eTSTthird.setFeeReceiver(feeReceiver);

        eTSTforth = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTforth.setHookConfig(address(0), 0);
        eTSTforth.setInterestRateModel(address(new IRMTestDefault()));
        eTSTforth.setMaxLiquidationDiscount(0.2e4);
        eTSTforth.setFeeReceiver(feeReceiver);

        eTSTfifth = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTfifth.setHookConfig(address(0), 0);
        eTSTfifth.setInterestRateModel(address(new IRMTestDefault()));
        eTSTfifth.setMaxLiquidationDiscount(0.2e4);
        eTSTfifth.setFeeReceiver(feeReceiver);

        eTSTsixth = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTSTsixth.setHookConfig(address(0), 0);
        eTSTsixth.setInterestRateModel(address(new IRMTestDefault()));
        eTSTsixth.setMaxLiquidationDiscount(0.2e4);
        eTSTsixth.setFeeReceiver(feeReceiver);
    }
}
