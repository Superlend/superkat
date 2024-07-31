// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    Test,
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationVault,
    ErrorsLib,
    IERC4626,
    AggAmountCapLib,
    AggAmountCap
} from "../../common/EulerAggregationVaultBase.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Actor} from "../util/Actor.sol";
import {Strategy} from "../util/Strategy.sol";

contract EulerAggregationVaultHandler is Test {
    using AggAmountCapLib for AggAmountCap;

    Actor internal actorUtil;
    Strategy internal strategyUtil;
    EulerAggregationVault internal eulerAggVault;

    // ghost vars
    uint256 public ghost_totalAllocationPoints;
    uint256 public ghost_totalAssetsDeposited;
    mapping(address => uint256) public ghost_allocationPoints;
    address[] public ghost_feeRecipients;
    mapping(address => uint256) public ghost_accumulatedPerformanceFeePerRecipient;
    uint256 public ghost_withdrawalQueueLength;

    // last function call state
    address currentActor;
    uint256 currentActorIndex;
    bool success;
    bytes returnData;

    constructor(EulerAggregationVault _eulerAggVault, Actor _actor, Strategy _strategy) {
        eulerAggVault = _eulerAggVault;
        actorUtil = _actor;
        strategyUtil = _strategy;

        // initiating ghost total allocation points to match count cash reserve.
        ghost_totalAllocationPoints += eulerAggVault.totalAllocationPoints();
        ghost_allocationPoints[address(0)] = ghost_totalAllocationPoints;
    }

    function setFeeRecipient(string calldata _feeRecipientSeed) external {
        address feeRecipientAddr = makeAddr(_feeRecipientSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.setFeeRecipient.selector, feeRecipientAddr)
        );

        if (success) {
            ghost_feeRecipients.push(feeRecipientAddr);
            actorUtil.setAsFeeReceiver(feeRecipientAddr);
        }
        (address feeRecipient,) = eulerAggVault.performanceFeeConfig();
        assertEq(feeRecipient, feeRecipientAddr);
    }

    function setPerformanceFee(uint96 _newFee) external {
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(eulerAggVault), abi.encodeWithSelector(EulerAggregationVault.setPerformanceFee.selector, _newFee)
        );

        (, uint96 fee) = eulerAggVault.performanceFeeConfig();

        assertEq(_newFee, fee);
    }

    function adjustAllocationPoints(uint256 _strategyIndexSeed, uint256 _newPoints) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggVault.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.adjustAllocationPoints.selector, strategyAddr, _newPoints)
        );

        if (success) {
            ghost_totalAllocationPoints = ghost_totalAllocationPoints + _newPoints - strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = _newPoints;
        }
        IEulerAggregationVault.Strategy memory strategyAfter = eulerAggVault.getStrategy(strategyAddr);
        assertEq(eulerAggVault.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function setStrategyCap(uint256 _strategyIndexSeed, uint16 _cap) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        uint256 strategyCapAmount = AggAmountCap.wrap(_cap).resolve();
        vm.assume(strategyCapAmount <= eulerAggVault.MAX_CAP_AMOUNT());

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggVault.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.setStrategyCap.selector, strategyAddr, _cap)
        );

        IEulerAggregationVault.Strategy memory strategyAfter = eulerAggVault.getStrategy(strategyAddr);
        if (success) {
            assertEq(AggAmountCap.unwrap(strategyAfter.cap), _cap);
        } else {
            assertEq(AggAmountCap.unwrap(strategyAfter.cap), AggAmountCap.unwrap(strategyBefore.cap));
        }
    }

    function toggleStrategyEmergencyStatus(uint256 _strategyIndexSeed) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        // simulating loss when switching strategy to emergency status
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggVault.getStrategy(strategyAddr);
        uint256 cached_ghost_totalAssetsDeposited =
            _simulateLossSocialization(ghost_totalAssetsDeposited, strategyBefore.allocated);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.toggleStrategyEmergencyStatus.selector, strategyAddr)
        );

        IEulerAggregationVault.Strategy memory strategyAfter = eulerAggVault.getStrategy(strategyAddr);
        if (success) {
            if (strategyAfter.status == IEulerAggregationVault.StrategyStatus.Emergency) {
                ghost_totalAllocationPoints -= strategyAfter.allocationPoints;
                ghost_totalAssetsDeposited = cached_ghost_totalAssetsDeposited;
            } else if (strategyAfter.status == IEulerAggregationVault.StrategyStatus.Active) {
                ghost_totalAllocationPoints += strategyAfter.allocationPoints;
                ghost_totalAssetsDeposited += strategyAfter.allocated;
            }
        }
    }

    function addStrategy(uint256 _strategyIndexSeed, uint256 _allocationPoints) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.addStrategy.selector, strategyAddr, _allocationPoints)
        );

        if (success) {
            ghost_totalAllocationPoints += _allocationPoints;
            ghost_allocationPoints[strategyAddr] = _allocationPoints;
            ghost_withdrawalQueueLength += 1;
        }
        IEulerAggregationVault.Strategy memory strategyAfter = eulerAggVault.getStrategy(strategyAddr);
        assertEq(eulerAggVault.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function removeStrategy(uint256 _strategyIndexSeed) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggVault.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.removeStrategy.selector, strategyAddr)
        );

        if (success) {
            ghost_totalAllocationPoints -= strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = 0;
            ghost_withdrawalQueueLength -= 1;
        }

        IEulerAggregationVault.Strategy memory strategyAfter = eulerAggVault.getStrategy(strategyAddr);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
        assertEq(eulerAggVault.totalAllocationPoints(), ghost_totalAllocationPoints);
    }

    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) external {
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.reorderWithdrawalQueue.selector, _index1, _index2)
        );
    }

    function rebalance(uint256 _actorIndexSeed) external {
        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (address[] memory strategiesToRebalance) = eulerAggVault.withdrawalQueue();
        (currentActor, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.rebalance.selector, strategiesToRebalance)
        );

        for (uint256 i; i < strategiesToRebalance.length; i++) {
            assertEq(
                IERC4626(strategiesToRebalance[i]).maxWithdraw(address(eulerAggVault)),
                (eulerAggVault.getStrategy(strategiesToRebalance[i])).allocated
            );
        }
    }

    function harvest(uint256 _actorIndexSeed) external {
        // track total yield and total loss to simulate loss socialization
        uint256 totalYield;
        uint256 totalLoss;
        // check if performance fee is on; store received fee per recipient if call is succesfull
        (address feeRecipient, uint256 performanceFee) = eulerAggVault.performanceFeeConfig();
        uint256 accumulatedPerformanceFee;
        uint256 cached_ghost_totalAssetsDeposited = ghost_totalAssetsDeposited;
        if (feeRecipient != address(0) && performanceFee > 0) {
            accumulatedPerformanceFee = ghost_accumulatedPerformanceFeePerRecipient[feeRecipient];
            address[] memory withdrawalQueueArray = eulerAggVault.withdrawalQueue();

            for (uint256 i; i < withdrawalQueueArray.length; i++) {
                uint256 allocated = (eulerAggVault.getStrategy(withdrawalQueueArray[i])).allocated;
                uint256 underlying = IERC4626(withdrawalQueueArray[i]).maxWithdraw(address(eulerAggVault));
                if (underlying >= allocated) {
                    totalYield += underlying - allocated;
                } else {
                    totalLoss += allocated - underlying;
                }
            }

            if (totalYield > totalLoss) {
                uint256 performancefeeAssets = Math.mulDiv(totalYield, performanceFee, 1e18, Math.Rounding.Floor);

                accumulatedPerformanceFee = eulerAggVault.previewDeposit(performancefeeAssets);
                cached_ghost_totalAssetsDeposited += performancefeeAssets;
            } else if (totalYield < totalLoss) {
                cached_ghost_totalAssetsDeposited =
                    _simulateLossSocialization(cached_ghost_totalAssetsDeposited, totalLoss);
            }
        }

        // simulate loss
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(eulerAggVault), abi.encodeWithSelector(IEulerAggregationVault.harvest.selector)
        );

        if (success) {
            ghost_accumulatedPerformanceFeePerRecipient[feeRecipient] = accumulatedPerformanceFee;
            ghost_totalAssetsDeposited = cached_ghost_totalAssetsDeposited;
        }
    }

    function updateInterestAccrued(uint256 _actorIndexSeed) external {
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(eulerAggVault),
            abi.encodeWithSelector(EulerAggregationVault.updateInterestAccrued.selector)
        );
    }

    function gulp(uint256 _actorIndexSeed) external {
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(eulerAggVault), abi.encodeWithSelector(EulerAggregationVault.gulp.selector)
        );

        if (success) {
            assertEq(
                eulerAggVault.totalAssetsAllocatable(),
                eulerAggVault.totalAssetsDeposited() + (eulerAggVault.getAggregationVaultSavingRate()).interestLeft
            );
        }
    }

    function deposit(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        if (eulerAggVault.totalSupply() == 0) {
            uint256 minAssets = eulerAggVault.previewMint(eulerAggVault.MIN_SHARES_FOR_GULP());
            vm.assume(_assets >= minAssets);
        }
        _fillBalance(currentActor, eulerAggVault.asset(), _assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggVault),
            abi.encodeWithSelector(IERC4626.deposit.selector, _assets, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += _assets;
        }
        assertEq(eulerAggVault.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function mint(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        if (eulerAggVault.totalSupply() == 0) {
            vm.assume(_shares >= eulerAggVault.MIN_SHARES_FOR_GULP());
        }

        uint256 assets = eulerAggVault.previewMint(_shares);
        _fillBalance(currentActor, eulerAggVault.asset(), assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggVault),
            abi.encodeWithSelector(IERC4626.mint.selector, _shares, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += assets;
        }
        assertEq(eulerAggVault.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function withdraw(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggVault),
            abi.encodeWithSelector(IERC4626.withdraw.selector, _assets, _receiver, currentActor)
        );

        if (success) {
            ghost_totalAssetsDeposited -= _assets;
        }
        assertEq(eulerAggVault.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function redeem(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));
        vm.assume(!actorUtil.isFeeReceiver(_receiver));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggVault),
            abi.encodeWithSelector(IERC4626.redeem.selector, _shares, _receiver, currentActor)
        );

        if (success) {
            uint256 assets = abi.decode(returnData, (uint256));
            ghost_totalAssetsDeposited -= assets;
        }
        assertEq(eulerAggVault.totalAssetsDeposited(), ghost_totalAssetsDeposited);
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
        asset.approve(address(eulerAggVault), _amount);
    }

    // This function simulate loss socialization, the part related to decreasing totalAssetsDeposited only.
    // Return the expected ghost_totalAssetsDeposited after loss socialization.
    function _simulateLossSocialization(uint256 cachedGhostTotalAssetsDeposited, uint256 _loss)
        private
        view
        returns (uint256)
    {
        IEulerAggregationVault.AggregationVaultSavingRate memory avsr = eulerAggVault.getAggregationVaultSavingRate();
        if (_loss > avsr.interestLeft) {
            cachedGhostTotalAssetsDeposited -= _loss - avsr.interestLeft;
        }

        return cachedGhostTotalAssetsDeposited;
    }
}
