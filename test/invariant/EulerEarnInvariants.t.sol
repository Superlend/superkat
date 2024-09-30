// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";
import {ActorUtil} from "./util/ActorUtil.sol";
import {StrategyUtil} from "./util/StrategyUtil.sol";
import {EulerEarnHandler} from "./handler/EulerEarnHandler.sol";

contract EulerEarnInvariants is EulerEarnBase {
    ActorUtil internal actorUtil;
    StrategyUtil internal strategyUtil;

    EulerEarnHandler internal eulerEulerEarnVaultHandler;

    // other strategies
    IEVault eTSTsecond;
    IEVault eTSTthird;
    IEVault eTSTforth;
    IEVault eTSTfifth;
    IEVault eTSTsixth;

    function setUp() public override {
        super.setUp();

        actorUtil = new ActorUtil(address(eulerEulerEarnVault));
        actorUtil.includeActor(manager);
        actorUtil.includeActor(deployer);
        actorUtil.includeActor(user1);
        actorUtil.includeActor(user2);

        strategyUtil = new StrategyUtil();
        strategyUtil.includeStrategy(address(eTST));
        _deployOtherStrategies();
        strategyUtil.includeStrategy(address(eTSTsecond));
        strategyUtil.includeStrategy(address(eTSTthird));
        strategyUtil.includeStrategy(address(eTSTforth));
        strategyUtil.includeStrategy(address(eTSTfifth));
        strategyUtil.includeStrategy(address(eTSTsixth));
        // cash reserve strategy
        strategyUtil.includeStrategy(address(0));

        eulerEulerEarnVaultHandler = new EulerEarnHandler(eulerEulerEarnVault, actorUtil, strategyUtil);

        targetContract(address(eulerEulerEarnVaultHandler));
    }

    // Right after gulp, total assets allocatable should be always equal to total assets deposited + interest left.
    function invariant_gulp() public {
        eulerEulerEarnVault.gulp();

        if (eulerEulerEarnVault.totalSupply() > 0) {
            (,, uint168 interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();
            assertEq(
                eulerEulerEarnVault.totalAssetsAllocatable(), eulerEulerEarnVault.totalAssetsDeposited() + interestLeft
            );
        }
    }

    // totalAssetsDeposited should be equal to the totalAssetsAllocatable after SMEAR has passed.
    function invariant_totalAssets() public {
        eulerEulerEarnVault.gulp();
        skip(ConstantsLib.INTEREST_SMEAR); // make sure smear has passed
        eulerEulerEarnVault.updateInterestAccrued();

        if (eulerEulerEarnVault.totalSupply() > 0) {
            assertEq(eulerEulerEarnVault.totalAssets(), eulerEulerEarnVault.totalAssetsAllocatable());
        }
    }

    // total allocation points should be equal to the sum of the allocation points of all strategies.
    function invariant_totalAllocationPoints() public view {
        address[] memory withdrawalQueueArray = eulerEulerEarnVault.withdrawalQueue();

        uint256 expectedTotalAllocationpoints;
        expectedTotalAllocationpoints += (eulerEulerEarnVault.getStrategy(address(0))).allocationPoints;
        for (uint256 i; i < withdrawalQueueArray.length; i++) {
            IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(withdrawalQueueArray[i]);

            if (strategy.status == IEulerEarn.StrategyStatus.Active) {
                expectedTotalAllocationpoints += strategy.allocationPoints;
            }
        }

        assertEq(eulerEulerEarnVault.totalAllocationPoints(), expectedTotalAllocationpoints);
    }

    // (1) If withdrawal queue length == 0, then the total allocation points should be equal cash reserve allocation points.
    // (2) If length > 0 and the total allocation points == cash reserve allocation points, then every strategy should have a 0 allocation points or should be a strategy in EMERGENCY mode.
    // (3) withdrawal queue length should always be equal the ghost length variable.
    function invariant_withdrawalQueue() public view {
        (address[] memory withdrawalQueueArray) = eulerEulerEarnVault.withdrawalQueue();

        uint256 cashReserveAllocationPoints = (eulerEulerEarnVault.getStrategy(address(0))).allocationPoints;

        if (withdrawalQueueArray.length == 0) {
            assertEq(eulerEulerEarnVault.totalAllocationPoints(), cashReserveAllocationPoints);
        }

        if (
            withdrawalQueueArray.length > 0
                && eulerEulerEarnVault.totalAllocationPoints() == cashReserveAllocationPoints
        ) {
            for (uint256 i; i < withdrawalQueueArray.length; i++) {
                IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(withdrawalQueueArray[i]);
                assertEq(strategy.allocationPoints == 0 || strategy.status == IEulerEarn.StrategyStatus.Emergency, true);
            }
        }

        assertEq(withdrawalQueueArray.length, eulerEulerEarnVaultHandler.ghost_withdrawalQueueLength());
    }

    // total allocated amount should always be equal the sum of allocated amount in all the strategies.
    function invariant_totalAllocated() public view {
        (address[] memory withdrawalQueueArray) = eulerEulerEarnVault.withdrawalQueue();

        uint256 aggregatedAllocatedAmount;
        for (uint256 i; i < withdrawalQueueArray.length; i++) {
            IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(withdrawalQueueArray[i]);

            if (strategy.status == IEulerEarn.StrategyStatus.Active) {
                aggregatedAllocatedAmount += strategy.allocated;
            }
        }

        assertEq(eulerEulerEarnVault.totalAllocated(), aggregatedAllocatedAmount);
    }

    // Balance of a certain fee recipient should always be equal to the ghost tracking variable.
    function invariant_performanceFee() public view {
        for (uint256 i; i < eulerEulerEarnVaultHandler.ghostFeeRecipientsLength(); i++) {
            address feeRecipient = eulerEulerEarnVaultHandler.ghost_feeRecipients(i);

            assertEq(
                eulerEulerEarnVault.balanceOf(feeRecipient),
                eulerEulerEarnVaultHandler.ghost_accumulatedPerformanceFeePerRecipient(feeRecipient)
            );
        }
    }

    // The interest left should always be greater or equal current interest accrued value.
    function invariant_interestLeft() public view {
        (,, uint168 interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();
        uint256 accruedInterest = eulerEulerEarnVault.interestAccrued();
        assertGe(interestLeft, accruedInterest);
    }

    function invariant_cashReserveStrategyCap() public view {
        assertEq(AggAmountCap.unwrap(eulerEulerEarnVault.getStrategy(address(0)).cap), 0);
    }

    // All actors voting power should always be equal to their shares balance.
    // All actor by default are self delegating.
    function invariant_votingPower() public view {
        address[] memory actorsList = actorUtil.getActors();

        for (uint256 i; i < actorsList.length; i++) {
            assertEq(eulerEulerEarnVault.balanceOf(actorsList[i]), eulerEulerEarnVault.getVotes(actorsList[i]));
        }
    }

    // lastHarvestTimestamp should always be equal to the expected ghost_lastHarvestTimestamp variable.
    // lastHarvestTimestamp is only updated through a direct `harvest()` call, harvesting while withdraw or redeem.
    // lastHarvestTimestamp does not get updated when a harvest is executed while rebalancing, as `rebalance()` does not guarantee
    // a harvest to all the strategies in withdrawal queue.
    function invariant_lastHarvestTimestamp() public view {
        assertEq(eulerEulerEarnVault.lastHarvestTimestamp(), eulerEulerEarnVaultHandler.ghost_lastHarvestTimestamp());
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
