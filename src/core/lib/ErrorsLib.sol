// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error Reentrancy();
    error ArrayLengthMismatch();
    error InitialAllocationPointsZero();
    error NegativeYield();
    error InactiveStrategy();
    error InvalidStrategyAsset();
    error StrategyAlreadyExist();
    error AlreadyRemoved();
    error PerformanceFeeAlreadySet();
    error MaxPerformanceFeeExceeded();
    error FeeRecipientNotSet();
    error FeeRecipientAlreadySet();
    error CanNotRemoveCashReserve();
    error DuplicateInitialStrategy();
    error NotSupported();
    error AlreadyEnabled();
    error AlreadyDisabled();
    error InvalidHooksTarget();
    error NotHooksContract();
    error InvalidHookedFns();
    error EmptyError();
    error NotWithdrawaQueue();
    error InvalidPlugin();
    error NotRebalancer();
}
