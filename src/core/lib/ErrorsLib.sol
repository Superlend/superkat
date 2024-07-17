// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error Reentrancy();
    error InitialAllocationPointsZero();
    error InactiveStrategy();
    error InvalidStrategyAsset();
    error StrategyAlreadyExist();
    error AlreadyRemoved();
    error PerformanceFeeAlreadySet();
    error MaxPerformanceFeeExceeded();
    error FeeRecipientNotSet();
    error CanNotRemoveCashReserve();
    error NotSupported();
    error AlreadyEnabled();
    error AlreadyDisabled();
    error InvalidHooksTarget();
    error NotHooksContract();
    error InvalidHookedFns();
    error EmptyError();
    error NotWithdrawaQueue();
    error InvalidRebalancerPlugin();
    error NotRebalancer();
    error InvalidAllocationPoints();
    error CanNotRemoveStartegyWithAllocatedAmount();
    error NoCapOnCashReserveStrategy();
    error CanNotAdjustAllocationPoints();
    error CanNotToggleStrategyEmergencyStatus();
    error CanNotRemoveStrategyInEmergencyStatus();
}
