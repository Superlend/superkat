// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../common/EulerEarnBase.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ActorUtil} from "../util/ActorUtil.sol";
import {StrategyUtil} from "../util/StrategyUtil.sol";

contract EulerEarnHandler is Test {
    using AggAmountCapLib for AggAmountCap;

    ActorUtil internal actorUtil;
    StrategyUtil internal strategyUtil;
    EulerEarn internal eulerEarn;

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

    constructor(EulerEarn _eulerEarn, ActorUtil _actor, StrategyUtil _strategy) {
        eulerEarn = _eulerEarn;
        actorUtil = _actor;
        strategyUtil = _strategy;

        // initiating ghost total allocation points to match count cash reserve.
        ghost_totalAllocationPoints += eulerEarn.totalAllocationPoints();
        ghost_allocationPoints[address(0)] = ghost_totalAllocationPoints;
    }

    function setFeeRecipient(string calldata _feeRecipientSeed) external {
        address feeRecipientAddr = makeAddr(_feeRecipientSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(eulerEarn), abi.encodeWithSelector(EulerEarn.setFeeRecipient.selector, feeRecipientAddr)
        );

        if (success) {
            ghost_feeRecipients.push(feeRecipientAddr);
            actorUtil.setAsFeeReceiver(feeRecipientAddr);
        }
        (address feeRecipient,) = eulerEarn.performanceFeeConfig();
        assertEq(feeRecipient, feeRecipientAddr);
    }

    function setPerformanceFee(uint96 _newFee, string calldata _feeRecipientSeed) external {
        _newFee = uint96(bound(_newFee, 0, ConstantsLib.MAX_PERFORMANCE_FEE));

        if (_newFee > 0) {
            address feeRecipientAddr = makeAddr(_feeRecipientSeed);

            (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
                0, address(eulerEarn), abi.encodeWithSelector(EulerEarn.setFeeRecipient.selector, feeRecipientAddr)
            );

            if (success) {
                ghost_feeRecipients.push(feeRecipientAddr);
                actorUtil.setAsFeeReceiver(feeRecipientAddr);
            }
        }

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(eulerEarn), abi.encodeWithSelector(EulerEarn.setPerformanceFee.selector, _newFee)
        );

        (, uint96 fee) = eulerEarn.performanceFeeConfig();

        assertEq(_newFee, fee);
    }

    function adjustAllocationPoints(uint256 _strategyIndexSeed, uint256 _newPoints) external {
        // allow strategyAddr == address(0) for cash reserve
        address strategyAddr = strategyUtil.fetchActiveStrategy(_strategyIndexSeed);

        IEulerEarn.Strategy memory strategyBefore = eulerEarn.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerEarn),
            abi.encodeWithSelector(EulerEarn.adjustAllocationPoints.selector, strategyAddr, _newPoints)
        );

        if (success) {
            ghost_totalAllocationPoints = ghost_totalAllocationPoints + _newPoints - strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = _newPoints;
        }
        IEulerEarn.Strategy memory strategyAfter = eulerEarn.getStrategy(strategyAddr);
        assertEq(eulerEarn.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function setStrategyCap(uint256 _strategyIndexSeed, uint16 _cap) external {
        address strategyAddr = strategyUtil.fetchActiveStrategy(_strategyIndexSeed);

        if (strategyAddr == address(0)) return;

        uint256 strategyCapAmount = AggAmountCap.wrap(_cap).resolve();
        if (strategyCapAmount > ConstantsLib.MAX_CAP_AMOUNT) strategyCapAmount = ConstantsLib.MAX_CAP_AMOUNT;

        IEulerEarn.Strategy memory strategyBefore = eulerEarn.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(eulerEarn), abi.encodeWithSelector(EulerEarn.setStrategyCap.selector, strategyAddr, _cap)
        );

        IEulerEarn.Strategy memory strategyAfter = eulerEarn.getStrategy(strategyAddr);
        if (success) {
            assertEq(AggAmountCap.unwrap(strategyAfter.cap), _cap);
        } else {
            assertEq(AggAmountCap.unwrap(strategyAfter.cap), AggAmountCap.unwrap(strategyBefore.cap));
        }
    }

    function toggleStrategyEmergencyStatus(uint256 _strategyIndexSeed, bool _isInitiallyActive) external {
        address strategyAddr = strategyUtil.fetchActiveOrEmergencyStrategy(_strategyIndexSeed, _isInitiallyActive);
        if (strategyAddr == address(0)) {
            _isInitiallyActive = !_isInitiallyActive;
            strategyAddr = strategyUtil.fetchActiveOrEmergencyStrategy(_strategyIndexSeed, _isInitiallyActive);
        }

        if (strategyAddr == address(0)) return;

        // simulating loss when switching strategy to emergency status
        uint256 expected_ghost_totalAssetsDeposited;
        if (_isInitiallyActive) {
            IEulerEarn.Strategy memory strategyBefore = eulerEarn.getStrategy(strategyAddr);
            expected_ghost_totalAssetsDeposited =
                _simulateLossDeduction(ghost_totalAssetsDeposited, strategyBefore.allocated);
        }

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerEarn),
            abi.encodeWithSelector(EulerEarn.toggleStrategyEmergencyStatus.selector, strategyAddr)
        );

        IEulerEarn.Strategy memory strategyAfter = eulerEarn.getStrategy(strategyAddr);
        if (success) {
            if (strategyAfter.status == IEulerEarn.StrategyStatus.Emergency) {
                ghost_totalAllocationPoints -= strategyAfter.allocationPoints;
                ghost_totalAssetsDeposited = expected_ghost_totalAssetsDeposited;

                strategyUtil.fromActiveToEmergency(strategyAddr);
            } else if (strategyAfter.status == IEulerEarn.StrategyStatus.Active) {
                ghost_totalAllocationPoints += strategyAfter.allocationPoints;

                strategyUtil.fromEmergencyToActive(strategyAddr);
            }
        }
    }

    function addStrategy(uint256 _strategyIndexSeed, uint256 _allocationPoints) external {
        address[] memory withdrawalQueue = eulerEarn.withdrawalQueue();
        if (withdrawalQueue.length == ConstantsLib.MAX_STRATEGIES) return;

        address strategyAddr = strategyUtil.fetchNonActiveStrategy(_strategyIndexSeed);
        if (strategyAddr == address(0)) return;

        _allocationPoints = bound(_allocationPoints, 1, type(uint96).max);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerEarn),
            abi.encodeWithSelector(EulerEarn.addStrategy.selector, strategyAddr, _allocationPoints)
        );

        if (success) {
            ghost_totalAllocationPoints += _allocationPoints;
            ghost_allocationPoints[strategyAddr] = _allocationPoints;
            ghost_withdrawalQueueLength += 1;

            strategyUtil.fromNonActiveToActive(strategyAddr);
        }

        IEulerEarn.Strategy memory strategyAfter = eulerEarn.getStrategy(strategyAddr);
        assertEq(eulerEarn.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function removeStrategy(uint256 _strategyIndexSeed) external {
        address strategyAddr = strategyUtil.fetchActiveStrategy(_strategyIndexSeed);
        if (strategyAddr == address(0)) return;

        IEulerEarn.Strategy memory strategyBefore = eulerEarn.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(eulerEarn), abi.encodeWithSelector(EulerEarn.removeStrategy.selector, strategyAddr)
        );

        if (success) {
            ghost_totalAllocationPoints -= strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = 0;
            ghost_withdrawalQueueLength -= 1;

            strategyUtil.fromActiveToNonActive(strategyAddr);
        }

        IEulerEarn.Strategy memory strategyAfter = eulerEarn.getStrategy(strategyAddr);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
        assertEq(eulerEarn.totalAllocationPoints(), ghost_totalAllocationPoints);
    }

    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) external {
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(eulerEarn), abi.encodeWithSelector(EulerEarn.reorderWithdrawalQueue.selector, _index1, _index2)
        );
    }

    function rebalance(uint256 _actorIndexSeed) external {
        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (address[] memory strategiesToRebalance) = eulerEarn.withdrawalQueue();
        (currentActor, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(eulerEarn),
            abi.encodeWithSelector(EulerEarn.rebalance.selector, strategiesToRebalance)
        );

        if (success) {
            ghost_lastHarvestTimestamp = uint40(block.timestamp);

            for (uint256 i; i < strategiesToRebalance.length; i++) {
                assertEq(
                    IERC4626(strategiesToRebalance[i]).maxWithdraw(address(eulerEarn)),
                    (eulerEarn.getStrategy(strategiesToRebalance[i])).allocated
                );
            }
        }
    }

    function harvest(uint256 _actorIndexSeed) external {
        uint256 expectedInterestRate = eulerEarn.interestAccrued();
        (uint256 expectedAccumulatedPerformanceFee, uint256 expectedTotalAssetsDeposited) =
            _simulateHarvest(ghost_totalAssetsDeposited + expectedInterestRate);

        // simulate loss
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(eulerEarn), abi.encodeWithSelector(IEulerEarn.harvest.selector)
        );

        if (success) {
            (address feeRecipient,) = eulerEarn.performanceFeeConfig();
            ghost_accumulatedPerformanceFeePerRecipient[feeRecipient] = expectedAccumulatedPerformanceFee;
            ghost_totalAssetsDeposited = expectedTotalAssetsDeposited;
            ghost_lastHarvestTimestamp = uint40(block.timestamp);
        }
    }

    function updateInterestAccrued(uint256 _actorIndexSeed) external {
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(eulerEarn), abi.encodeWithSelector(EulerEarn.updateInterestAccrued.selector)
        );
    }

    function gulp(uint256 _actorIndexSeed) external {
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(eulerEarn), abi.encodeWithSelector(EulerEarn.gulp.selector)
        );

        if (success && eulerEarn.totalSupply() > 0) {
            (,, uint168 interestLeft) = eulerEarn.getEulerEarnSavingRate();

            assertEq(eulerEarn.totalAssetsAllocatable(), eulerEarn.totalAssetsDeposited() + interestLeft);
        }
    }

    function deposit(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(actorUtil.isFeeReceiver(_receiver) == false);

        _assets = bound(_assets, 1, type(uint256).max);

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        _fillBalance(currentActor, eulerEarn.asset(), _assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex, address(eulerEarn), abi.encodeWithSelector(IERC4626.deposit.selector, _assets, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += _assets;
        }
        assertEq(eulerEarn.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function mint(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(actorUtil.isFeeReceiver(_receiver) == false);

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        _shares = bound(_shares, 1, type(uint256).max);

        uint256 assets = eulerEarn.previewMint(_shares);
        _fillBalance(currentActor, eulerEarn.asset(), assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex, address(eulerEarn), abi.encodeWithSelector(IERC4626.mint.selector, _shares, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += assets;
        }
        assertEq(eulerEarn.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function withdraw(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        uint256 expectedInterestRate = eulerEarn.interestAccrued();
        (uint256 expectedAccumulatedPerformanceFee, uint256 expectedTotalAssetsDeposited) =
            _simulateHarvest(ghost_totalAssetsDeposited + expectedInterestRate);

        uint256 previousHarvestTimestamp = eulerEarn.lastHarvestTimestamp();

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        _assets = bound(_assets, 0, eulerEarn.convertToAssets(eulerEarn.balanceOf(currentActor)));

        bool isOnlyCashReserveWithdraw = IERC20(eulerEarn.asset()).balanceOf(address(eulerEarn)) >= _assets;

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerEarn),
            abi.encodeWithSelector(IERC4626.withdraw.selector, _assets, _receiver, currentActor)
        );

        if (success) {
            if (
                block.timestamp > previousHarvestTimestamp + ConstantsLib.HARVEST_COOLDOWN
                    || isOnlyCashReserveWithdraw == false
            ) {
                (address feeRecipient,) = eulerEarn.performanceFeeConfig();
                ghost_accumulatedPerformanceFeePerRecipient[feeRecipient] = expectedAccumulatedPerformanceFee;
                ghost_totalAssetsDeposited = expectedTotalAssetsDeposited;

                ghost_lastHarvestTimestamp = uint40(block.timestamp);
            }

            ghost_totalAssetsDeposited -= _assets;
        }
        assertEq(eulerEarn.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function redeem(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        uint256 expectedInterestRate = eulerEarn.interestAccrued();

        (uint256 expectedAccumulatedPerformanceFee, uint256 expectedTotalAssetsDeposited) =
            _simulateHarvest(ghost_totalAssetsDeposited + expectedInterestRate);

        uint256 previousHarvestTimestamp = eulerEarn.lastHarvestTimestamp();

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        _shares = bound(_shares, 0, eulerEarn.balanceOf(currentActor));

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerEarn),
            abi.encodeWithSelector(IERC4626.redeem.selector, _shares, _receiver, currentActor)
        );

        bool isOnlyCashReserveWithdraw =
            IERC20(eulerEarn.asset()).balanceOf(address(eulerEarn)) >= eulerEarn.previewRedeem(_shares);

        if (success) {
            if (
                block.timestamp > previousHarvestTimestamp + ConstantsLib.HARVEST_COOLDOWN
                    || isOnlyCashReserveWithdraw == false
            ) {
                (address feeRecipient,) = eulerEarn.performanceFeeConfig();
                ghost_accumulatedPerformanceFeePerRecipient[feeRecipient] = expectedAccumulatedPerformanceFee;
                ghost_totalAssetsDeposited = expectedTotalAssetsDeposited;

                ghost_lastHarvestTimestamp = uint40(block.timestamp);
            }

            uint256 assets = abi.decode(returnData, (uint256));
            ghost_totalAssetsDeposited -= assets;
        }
        assertEq(eulerEarn.totalAssetsDeposited(), ghost_totalAssetsDeposited);
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
        asset.approve(address(eulerEarn), _amount);
    }

    // This function simulate loss socialization, the part related to decreasing totalAssetsDeposited only.
    // Return the expected ghost_totalAssetsDeposited after loss socialization.
    function _simulateLossDeduction(uint256 cachedGhostTotalAssetsDeposited, uint256 _loss)
        private
        view
        returns (uint256)
    {
        // (,, uint168 interestLeft) = eulerEarn.getEulerEarnSavingRate();
        uint256 totalNotDistributed = eulerEarn.totalAssetsAllocatable() - cachedGhostTotalAssetsDeposited;

        if (_loss > totalNotDistributed) {
            cachedGhostTotalAssetsDeposited -= (_loss - totalNotDistributed);
        }

        return cachedGhostTotalAssetsDeposited;
    }

    function _simulateHarvest(uint256 _totalAssetsDeposited) private view returns (uint256, uint256) {
        // track total yield and total loss to simulate loss socialization
        uint256 totalYield;
        uint256 totalLoss;

        // check if performance fee is on; store received fee per recipient if call is succesfull
        (address feeRecipient, uint256 performanceFee) = eulerEarn.performanceFeeConfig();
        uint256 accumulatedPerformanceFee = ghost_accumulatedPerformanceFeePerRecipient[feeRecipient];

        address[] memory withdrawalQueueArray = eulerEarn.withdrawalQueue();
        for (uint256 i; i < withdrawalQueueArray.length; i++) {
            uint256 allocated = (eulerEarn.getStrategy(withdrawalQueueArray[i])).allocated;
            uint256 underlying = IERC4626(withdrawalQueueArray[i]).maxWithdraw(address(eulerEarn));
            if (underlying >= allocated) {
                totalYield += underlying - allocated;
            } else {
                totalLoss += allocated - underlying;
            }
        }

        if (totalYield > totalLoss) {
            if (feeRecipient != address(0) && performanceFee > 0) {
                uint256 performancefeeAssets =
                    Math.mulDiv(totalYield - totalLoss, performanceFee, 1e18, Math.Rounding.Floor);
                accumulatedPerformanceFee = eulerEarn.previewDeposit(performancefeeAssets);

                _totalAssetsDeposited += performancefeeAssets;
            }
        } else if (totalYield < totalLoss) {
            _totalAssetsDeposited = _simulateLossDeduction(_totalAssetsDeposited, totalLoss - totalYield);
        }

        return (accumulatedPerformanceFee, _totalAssetsDeposited);
    }
}
