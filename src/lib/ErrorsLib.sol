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
    error YieldAggregatorRewardsNotSupported();
    error YieldAggregatorRewardsAlreadyEnabled();
    error YieldAggregatorRewardsAlreadyDisabled();
    error InvalidHooksTarget();
    error NotHooksContract();
    error InvalidHookedFns();
    error EmptyError();
    error InvalidAllocationPoints();
    error CanNotRemoveStrategyWithAllocatedAmount();
    error NoCapOnCashReserveStrategy();
    error CanNotToggleStrategyEmergencyStatus();
    error StrategyCapExceedMax();
    error OutOfBounds();
    error SameIndexes();
    error NotEnoughAssets();
    error MaxStrategiesExceeded();

    /// ERC4626Upgradeable.sol errors
    /// @dev Attempted to deposit more assets than the max amount for `receiver`.
    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);
    /// @dev Attempted to mint more shares than the max amount for `receiver`.
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);
    /// @dev Attempted to withdraw more assets than the max amount for `receiver`.
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
    /// @dev Attempted to redeem more shares than the max amount for `receiver`.
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    /// ERC20VotesUpgradeable.sol errors
    /// @dev Total supply cap has been exceeded, introducing a risk of votes overflowing.
    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);
}
