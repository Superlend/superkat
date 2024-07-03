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
    WithdrawalQueue
} from "../../common/EulerAggregationLayerBase.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Actor} from "../util/Actor.sol";
import {Strategy} from "../util/Strategy.sol";

contract EulerAggregationLayerHandler is Test {
    Actor internal actorUtil;
    Strategy internal strategyUtil;
    EulerAggregationLayer internal eulerAggLayer;
    WithdrawalQueue internal withdrawalQueue;

    // ghost vars
    uint256 ghost_totalAllocationPoints;
    uint256 ghost_totalAssetsDeposited;
    mapping(address => uint256) ghost_allocationPoints;
    address[] public ghost_feeRecipients;
    mapping(address => uint256) public ghost_accumulatedPerformanceFeePerRecipient;

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

        // initiating ghost total allocation points to match count cash reserve.
        ghost_totalAllocationPoints += eulerAggLayer.totalAllocationPoints();
        ghost_allocationPoints[address(0)] = ghost_totalAllocationPoints;
    }

    function setFeeRecipient(string calldata _feeRecipientSeed) external {
        address feeRecipientAddr = makeAddr(_feeRecipientSeed);
        // vm.assume(_newFeeRecipient != address(0));

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggLayer),
            abi.encodeWithSelector(EulerAggregationLayer.setFeeRecipient.selector, feeRecipientAddr)
        );

        if (success) {
            ghost_feeRecipients.push(feeRecipientAddr);
        }
        (address feeRecipient,) = eulerAggLayer.performanceFeeConfig();
        assertEq(feeRecipient, feeRecipientAddr);
    }

    function setPerformanceFee(uint256 _newFee) external {
        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0, address(eulerAggLayer), abi.encodeWithSelector(EulerAggregationLayer.setPerformanceFee.selector, _newFee)
        );

        (, uint256 fee) = eulerAggLayer.performanceFeeConfig();

        assertEq(_newFee, fee);
    }

    function adjustAllocationPoints(uint256 _strategyIndexSeed, uint256 _newPoints) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggLayer.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggLayer),
            abi.encodeWithSelector(IEulerAggregationLayer.adjustAllocationPoints.selector, strategyAddr, _newPoints)
        );

        if (success) {
            ghost_totalAllocationPoints = ghost_totalAllocationPoints + _newPoints - strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = _newPoints;
        }
        IEulerAggregationLayer.Strategy memory strategyAfter = eulerAggLayer.getStrategy(strategyAddr);
        assertEq(eulerAggLayer.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function setStrategyCap(uint256 _strategyIndexSeed, uint256 _cap) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggLayer.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggLayer),
            abi.encodeWithSelector(EulerAggregationLayer.setStrategyCap.selector, strategyAddr, _cap)
        );

        IEulerAggregationLayer.Strategy memory strategyAfter = eulerAggLayer.getStrategy(strategyAddr);
        if (success) {
            assertEq(strategyAfter.cap, _cap);
        } else {
            assertEq(strategyAfter.cap, strategyBefore.cap);
        }
    }

    function addStrategy(uint256 _strategyIndexSeed, uint256 _allocationPoints) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggLayer),
            abi.encodeWithSelector(IEulerAggregationLayer.addStrategy.selector, strategyAddr, _allocationPoints)
        );

        if (success) {
            ghost_totalAllocationPoints += _allocationPoints;
            ghost_allocationPoints[strategyAddr] = _allocationPoints;
        }
        IEulerAggregationLayer.Strategy memory strategyAfter = eulerAggLayer.getStrategy(strategyAddr);
        assertEq(eulerAggLayer.totalAllocationPoints(), ghost_totalAllocationPoints);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
    }

    function removeStrategy(uint256 _strategyIndexSeed) external {
        address strategyAddr = strategyUtil.fetchStrategy(_strategyIndexSeed);

        IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggLayer.getStrategy(strategyAddr);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            0,
            address(eulerAggLayer),
            abi.encodeWithSelector(IEulerAggregationLayer.removeStrategy.selector, strategyAddr)
        );

        if (success) {
            ghost_totalAllocationPoints -= strategyBefore.allocationPoints;
            ghost_allocationPoints[strategyAddr] = 0;
        }

        IEulerAggregationLayer.Strategy memory strategyAfter = eulerAggLayer.getStrategy(strategyAddr);
        assertEq(strategyAfter.allocationPoints, ghost_allocationPoints[strategyAddr]);
        assertEq(eulerAggLayer.totalAllocationPoints(), ghost_totalAllocationPoints);
    }

    function harvest(uint256 _actorIndexSeed) external {
        // check if performance fee is on; store received fee per recipient if call is succesfull
        (address feeRecipient, uint256 performanceFee) = eulerAggLayer.performanceFeeConfig();
        uint256 accumulatedPerformanceFee;
        if (feeRecipient != address(0) && performanceFee > 0) {
            accumulatedPerformanceFee = ghost_accumulatedPerformanceFeePerRecipient[feeRecipient];
            (address[] memory withdrawalQueueArray, uint256 withdrawalQueueLength) =
                withdrawalQueue.getWithdrawalQueueArray();

            for (uint256 i; i < withdrawalQueueLength; i++) {
                uint256 allocated = (eulerAggLayer.getStrategy(withdrawalQueueArray[i])).allocated;
                uint256 underlying = IERC4626(withdrawalQueueArray[i]).maxWithdraw(address(eulerAggLayer));
                if (underlying > allocated) {
                    uint256 yield = underlying - allocated;
                    accumulatedPerformanceFee += Math.mulDiv(yield, performanceFee, 1e18, Math.Rounding.Floor);
                }
            }
        }

        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(eulerAggLayer), abi.encodeWithSelector(IEulerAggregationLayer.harvest.selector)
        );

        if (success) {
            ghost_accumulatedPerformanceFeePerRecipient[feeRecipient] = accumulatedPerformanceFee;
        }
    }

    function updateInterestAccrued(uint256 _actorIndexSeed) external {
        (, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed,
            address(eulerAggLayer),
            abi.encodeWithSelector(EulerAggregationLayer.updateInterestAccrued.selector)
        );
    }

    function deposit(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        _fillBalance(currentActor, eulerAggLayer.asset(), _assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggLayer),
            abi.encodeWithSelector(IERC4626.deposit.selector, _assets, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += _assets;
        }
        assertEq(eulerAggLayer.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function mint(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        uint256 assets = eulerAggLayer.previewMint(_shares);
        _fillBalance(currentActor, eulerAggLayer.asset(), assets);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggLayer),
            abi.encodeWithSelector(IERC4626.mint.selector, _shares, _receiver)
        );

        if (success) {
            ghost_totalAssetsDeposited += assets;
        }
        assertEq(eulerAggLayer.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function withdraw(uint256 _actorIndexSeed, uint256 _assets, address _receiver) external {
        vm.assume(_receiver != address(0));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggLayer),
            abi.encodeWithSelector(IERC4626.withdraw.selector, _assets, _receiver, currentActor)
        );

        if (success) {
            ghost_totalAssetsDeposited -= _assets;
        }
        assertEq(eulerAggLayer.totalAssetsDeposited(), ghost_totalAssetsDeposited);
    }

    function redeem(uint256 _actorIndexSeed, uint256 _shares, address _receiver) external {
        vm.assume(_receiver != address(0));

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(eulerAggLayer),
            abi.encodeWithSelector(IERC4626.redeem.selector, _shares, _receiver, currentActor)
        );

        if (success) {
            uint256 assets = abi.decode(returnData, (uint256));
            ghost_totalAssetsDeposited -= assets;
        }
        assertEq(eulerAggLayer.totalAssetsDeposited(), ghost_totalAssetsDeposited);
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
        asset.approve(address(eulerAggLayer), _amount);
    }
}
