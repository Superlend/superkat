// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    Test,
    YieldAggregatorBase,
    YieldAggregator,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IYieldAggregator,
    ErrorsLib,
    IERC4626,
    AggAmountCapLib,
    AggAmountCap,
    ConstantsLib
} from "../../common/YieldAggregatorBase.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Actor} from "../util/Actor.sol";
import {Strategy} from "../util/Strategy.sol";

contract YieldAggregatorHandler is Test {
    using AggAmountCapLib for AggAmountCap;

    Actor internal actorUtil;
    Strategy internal strategyUtil;
    YieldAggregator internal yieldAggregator;

    // ghost vars
    uint256 public ghost_totalAllocationPoints;
    uint256 public ghost_totalAssetsDeposited;
    mapping(address => uint256) public ghost_allocationPoints;
    address[] public ghost_feeRecipients;
    mapping(address => uint256) public ghost_accumulatedPerformanceFeePerRecipient;
    uint256 public ghost_withdrawalQueueLength;
    uint40 public ghost_lastHarvestTimestamp;

    // last function call state
    address currentActor;
    uint256 currentActorIndex;
    bool success;
    bytes returnData;

    constructor(YieldAggregator _yieldAggregator, Actor _actor, Strategy _strategy) {
        yieldAggregator = _yieldAggregator;
        actorUtil = _actor;
        strategyUtil = _strategy;

        // initiating ghost total allocation points to match count cash reserve.
        ghost_totalAllocationPoints += yieldAggregator.totalAllocationPoints();
        ghost_allocationPoints[address(0)] = ghost_totalAllocationPoints;
    }

    function setFeeRecipient(string calldata _feeRecipientSeed) external {
        address feeRecipientAddr = makeAddr(_feeRecipientSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.setFeeRecipient.selector, feeRecipientAddr)
        );

        if (success) {
            ghost_feeRecipients.push(feeRecipientAddr);
            actorUtil.setAsFeeReceiver(feeRecipientAddr);
        }
        (address feeRecipient,) = yieldAggregator.performanceFeeConfig();
        assertEq(feeRecipient, feeRecipientAddr);
    }

    function setPerformanceFee(uint96 _newFee) external {
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(yieldAggregator), abi.encodeWithSelector(YieldAggregator.setPerformanceFee.selector, _newFee)
        );

        (, uint96 fee) = yieldAggregator.performanceFeeConfig();

        assertEq(_newFee, fee);
    }

    function adjustAllocationPoints(uint256 _strategyIndexSeed, uint256 _newPoints) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        IYieldAggregator.Strategy memory strategyBefore = yieldAggregator.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.adjustAllocationPoints.selector, strategyAddr, _newPoints)
        );

        if (success) {
            ghost_totalAllocationPoints = ghost_totalAllocationPoints + _newPoints - strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = _newPoints;
        }
        IYieldAggregator.Strategy memory strategyAfter = yieldAggregator.getStrategy(strategyAddr);
        assertEq(yieldAggregator.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function setStrategyCap(uint256 _strategyIndexSeed, uint16 _cap) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        uint256 strategyCapAmount = AggAmountCap.wrap(_cap).resolve();
        vm.assume(strategyCapAmount <= ConstantsLib.MAX_CAP_AMOUNT);

        IYieldAggregator.Strategy memory strategyBefore = yieldAggregator.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.setStrategyCap.selector, strategyAddr, _cap)
        );

        IYieldAggregator.Strategy memory strategyAfter = yieldAggregator.getStrategy(strategyAddr);
        if (success) {
            assertEq(AggAmountCap.unwrap(strategyAfter.cap), _cap);
        } else {
            assertEq(AggAmountCap.unwrap(strategyAfter.cap), AggAmountCap.unwrap(strategyBefore.cap));
        }
    }

    function toggleStrategyEmergencyStatus(uint256 _strategyIndexSeed) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        // simulating loss when switching strategy to emergency status
        IYieldAggregator.Strategy memory strategyBefore = yieldAggregator.getStrategy(strategyAddr);
        uint256 cached_ghost_totalAssetsDeposited =
            _simulateLossSocialization(ghost_totalAssetsDeposited, strategyBefore.allocated);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.toggleStrategyEmergencyStatus.selector, strategyAddr)
        );

        IYieldAggregator.Strategy memory strategyAfter = yieldAggregator.getStrategy(strategyAddr);
        if (success) {
            if (strategyAfter.status == IYieldAggregator.StrategyStatus.Emergency) {
                ghost_totalAllocationPoints -= strategyAfter.allocationPoints;
                ghost_totalAssetsDeposited = cached_ghost_totalAssetsDeposited;
            } else if (strategyAfter.status == IYieldAggregator.StrategyStatus.Active) {
                ghost_totalAllocationPoints += strategyAfter.allocationPoints;
                ghost_totalAssetsDeposited += strategyAfter.allocated;
            }
        }
    }

    function addStrategy(uint256 _strategyIndexSeed, uint256 _allocationPoints) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.addStrategy.selector, strategyAddr, _allocationPoints)
        );

        if (success) {
            ghost_totalAllocationPoints += _allocationPoints;
            ghost_allocationPoints[strategyAddr] = _allocationPoints;
            ghost_withdrawalQueueLength += 1;
        }
        IYieldAggregator.Strategy memory strategyAfter = yieldAggregator.getStrategy(strategyAddr);
        assertEq(yieldAggregator.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function removeStrategy(uint256 _strategyIndexSeed) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        IYieldAggregator.Strategy memory strategyBefore = yieldAggregator.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(yieldAggregator), abi.encodeWithSelector(YieldAggregator.removeStrategy.selector, strategyAddr)
        );

        if (success) {
            ghost_totalAllocationPoints -= strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = 0;
            ghost_withdrawalQueueLength -= 1;
        }

        IYieldAggregator.Strategy memory strategyAfter = yieldAggregator.getStrategy(strategyAddr);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
        assertEq(yieldAggregator.totalAllocationPoints(), ghost_totalAllocationPoints);
    }

    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) external {
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.reorderWithdrawalQueue.selector, _index1, _index2)
        );
    }

    function rebalance(uint256 _actorIndexSeed) external {
        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (address[] memory strategiesToRebalance) = yieldAggregator.withdrawalQueue();
        (currentActor, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.rebalance.selector, strategiesToRebalance)
        );

        for (uint256 i; i < strategiesToRebalance.length; i++) {
            assertEq(
                IERC4626(strategiesToRebalance[i]).maxWithdraw(address(yieldAggregator)),
                (yieldAggregator.getStrategy(strategiesToRebalance[i])).allocated
            );
        }
    }

    function harvest(uint256 _actorIndexSeed) external {
        (uint256 expectedAccumulatedPerformanceFee, uint256 expectedTotalAssetsDeposited) =
            _simulateFeeAndLossSocialization();

        // simulate loss
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(yieldAggregator), abi.encodeWithSelector(IYieldAggregator.harvest.selector)
        );

        if (success) {
            (address feeRecipient,) = yieldAggregator.performanceFeeConfig();
            ghost_accumulatedPerformanceFeePerRecipient[feeRecipient] = expectedAccumulatedPerformanceFee;
            ghost_totalAssetsDeposited = expectedTotalAssetsDeposited;
            ghost_lastHarvestTimestamp = uint40(block.timestamp);
        }
    }

    function updateInterestAccrued(uint256 _actorIndexSeed) external {
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(yieldAggregator),
            abi.encodeWithSelector(YieldAggregator.updateInterestAccrued.selector)
        );
    }

    function gulp(uint256 _actorIndexSeed) external {
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(yieldAggregator), abi.encodeWithSelector(YieldAggregator.gulp.selector)
        );

        if (success) {
            (,, uint168 interestLeft) = yieldAggregator.getYieldAggregatorSavingRate();

            assertEq(yieldAggregator.totalAssetsAllocatable(), yieldAggregator.totalAssetsDeposited() + interestLeft);
        }
    }

    function deposit(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        if (yieldAggregator.totalSupply() == 0) {
            uint256 minAssets = yieldAggregator.previewMint(ConstantsLib.MIN_SHARES_FOR_GULP);
            vm.assume(_assets >= minAssets);
        }
        _fillBalance(currentActor, yieldAggregator.asset(), _assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(yieldAggregator),
            abi.encodeWithSelector(IERC4626.deposit.selector, _assets, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += _assets;
        }
        assertEq(yieldAggregator.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function mint(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        if (yieldAggregator.totalSupply() == 0) {
            vm.assume(_shares >= ConstantsLib.MIN_SHARES_FOR_GULP);
        }

        uint256 assets = yieldAggregator.previewMint(_shares);
        _fillBalance(currentActor, yieldAggregator.asset(), assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(yieldAggregator),
            abi.encodeWithSelector(IERC4626.mint.selector, _shares, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += assets;
        }
        assertEq(yieldAggregator.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function withdraw(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        uint256 previousHarvestTimestamp = yieldAggregator.lastHarvestTimestamp();
        (uint256 expectedAccumulatedPerformanceFee, uint256 expectedTotalAssetsDeposited) =
            _simulateFeeAndLossSocialization();

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(yieldAggregator),
            abi.encodeWithSelector(IERC4626.withdraw.selector, _assets, _receiver, currentActor)
        );

        if (success) {
            if (block.timestamp > previousHarvestTimestamp + ConstantsLib.HARVEST_COOLDOWN) {
                (address feeRecipient,) = yieldAggregator.performanceFeeConfig();
                ghost_accumulatedPerformanceFeePerRecipient[feeRecipient] = expectedAccumulatedPerformanceFee;
                ghost_totalAssetsDeposited = expectedTotalAssetsDeposited;

                ghost_lastHarvestTimestamp = uint40(block.timestamp);
            }

            ghost_totalAssetsDeposited -= _assets;
        }
        assertEq(yieldAggregator.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function redeem(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(yieldAggregator),
            abi.encodeWithSelector(IERC4626.redeem.selector, _shares, _receiver, currentActor)
        );

        if (success) {
            uint256 assets = abi.decode(returnData, (uint256));
            ghost_totalAssetsDeposited -= assets;
        }
        assertEq(yieldAggregator.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function ghostFeeRecipientsLength() external view returns (uint256) {
        return ghost_feeRecipients.length;
    }

    function _fillBalance(address _actor, address _asset, uint256 _amount) internal {
        TestERC20 asset = TestERC20(_asset);

        uint256 actorCurrentBalance = asset.balanceOf(currentActor);
        if (actorCurrentBalance < _amount) {
            asset.mint(currentActor, _amount - actorCurrentBalance);
        }
        vm.prank(_actor);
        asset.approve(address(yieldAggregator), _amount);
    }

    // This function simulate loss socialization, the part related to decreasing totalAssetsDeposited only.
    // Return the expected ghost_totalAssetsDeposited after loss socialization.
    function _simulateLossSocialization(uint256 cachedGhostTotalAssetsDeposited, uint256 _loss)
        private
        view
        returns (uint256)
    {
        (,, uint168 interestLeft) = yieldAggregator.getYieldAggregatorSavingRate();
        if (_loss > interestLeft) {
            cachedGhostTotalAssetsDeposited -= _loss - interestLeft;
        }

        return cachedGhostTotalAssetsDeposited;
    }

    function _simulateFeeAndLossSocialization() private view returns (uint256, uint256) {
        // track total yield and total loss to simulate loss socialization
        uint256 totalYield;
        uint256 totalLoss;
        // check if performance fee is on; store received fee per recipient if call is succesfull
        (address feeRecipient, uint256 performanceFee) = yieldAggregator.performanceFeeConfig();
        uint256 accumulatedPerformanceFee;
        uint256 cached_ghost_totalAssetsDeposited = ghost_totalAssetsDeposited;
        if (feeRecipient != address(0) && performanceFee > 0) {
            accumulatedPerformanceFee = ghost_accumulatedPerformanceFeePerRecipient[feeRecipient];
            address[] memory withdrawalQueueArray = yieldAggregator.withdrawalQueue();

            for (uint256 i; i < withdrawalQueueArray.length; i++) {
                uint256 allocated = (yieldAggregator.getStrategy(withdrawalQueueArray[i])).allocated;
                uint256 underlying = IERC4626(withdrawalQueueArray[i]).maxWithdraw(address(yieldAggregator));
                if (underlying >= allocated) {
                    totalYield += underlying - allocated;
                } else {
                    totalLoss += allocated - underlying;
                }
            }

            if (totalYield > totalLoss) {
                uint256 performancefeeAssets = Math.mulDiv(totalYield, performanceFee, 1e18, Math.Rounding.Floor);

                accumulatedPerformanceFee = yieldAggregator.previewDeposit(performancefeeAssets);
                cached_ghost_totalAssetsDeposited += performancefeeAssets;
            } else if (totalYield < totalLoss) {
                cached_ghost_totalAssetsDeposited =
                    _simulateLossSocialization(cached_ghost_totalAssetsDeposited, totalLoss);
            }
        }

        return (accumulatedPerformanceFee, cached_ghost_totalAssetsDeposited);
    }
}
