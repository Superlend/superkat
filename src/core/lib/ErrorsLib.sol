// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error Reentrancy();
    error InitialAllocationPointsZero();
    error InactiveStrategy();
    error InvalidStrategyAsset();
    error StrategyAlreadyExist();
    error StrategyShouldBeActive();
    error MaxPerformanceFeeExceeded();
    error FeeRecipientNotSet();
    error CanNotRemoveCashReserve();
    error AggVaultRewardsNotSupported();
    error AggVaultRewardsAlreadyEnabled();
    error AggVaultRewardsAlreadyDisabled();
    error InvalidHooksTarget();
    error NotHooksContract();
    error InvalidHookedFns();
    error EmptyError();
    error InvalidAllocationPoints();
    error CanNotRemoveStartegyWithAllocatedAmount();
    error NoCapOnCashReserveStrategy();
    error CanNotToggleStrategyEmergencyStatus();
    error CanNotRemoveStrategyInEmergencyStatus();
    error StrategyCapExceedMax();
    error OutOfBounds();
    error SameIndexes();
    error NotEnoughAssets();
}
