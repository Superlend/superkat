// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IBalanceForwarder} from "../interface/IBalanceForwarder.sol";
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";
import {IBalanceTracker} from "reward-streams/interfaces/IBalanceTracker.sol";
import {IRewardStreams} from "reward-streams/interfaces/IRewardStreams.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {StorageLib, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";

/// @title Rewards module
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A module to provide balancer tracking for reward streams and to integrate with strategies rewards.
/// @dev See https://github.com/euler-xyz/reward-streams.
abstract contract RewardsModule is IBalanceForwarder, Shared {
    /// @notice Opt in to strategy rewards
    /// @param _strategy Strategy address
    function optInStrategyRewards(address _strategy) external virtual nonReentrant {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if ($.strategies[_strategy].status == IEulerAggregationVault.StrategyStatus.Inactive) {
            revert Errors.InactiveStrategy();
        }

        IBalanceForwarder(_strategy).enableBalanceForwarder();

        emit Events.OptInStrategyRewards(_strategy);
    }

    /// @notice Opt out of strategy rewards
    /// @param _strategy Strategy address
    function optOutStrategyRewards(address _strategy) external virtual nonReentrant {
        IBalanceForwarder(_strategy).disableBalanceForwarder();

        emit Events.OptOutStrategyRewards(_strategy);
    }

    /// @notice Enable aggregation vault rewards for specific strategy's reward token.
    /// @param _strategy Strategy address.
    /// @param _reward Reward token address.
    function enableRewardForStrategy(address _strategy, address _reward) external virtual nonReentrant {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if ($.strategies[_strategy].status == IEulerAggregationVault.StrategyStatus.Inactive) {
            revert Errors.InactiveStrategy();
        }

        IRewardStreams(IBalanceForwarder(_strategy).balanceTrackerAddress()).enableReward(_strategy, _reward);

        emit Events.EnableRewardForStrategy(_strategy, _reward);
    }

    /// @notice Disable aggregation vault rewards for specific strategy's reward token.
    /// @param _strategy Strategy address.
    /// @param _reward Reward token address.
    /// @param _forfeitRecentReward Whether to forfeit the recent rewards or not.
    function disableRewardForStrategy(address _strategy, address _reward, bool _forfeitRecentReward)
        external
        virtual
        nonReentrant
    {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if ($.strategies[_strategy].status == IEulerAggregationVault.StrategyStatus.Inactive) {
            revert Errors.InactiveStrategy();
        }

        IRewardStreams(IBalanceForwarder(_strategy).balanceTrackerAddress()).disableReward(
            _strategy, _reward, _forfeitRecentReward
        );

        emit Events.DisableRewardForStrategy(_strategy, _reward, _forfeitRecentReward);
    }

    /// @notice Claim a specific strategy rewards
    /// @param _strategy Strategy address.
    /// @param _reward The address of the reward token.
    /// @param _recipient The address to receive the claimed reward tokens.
    /// @param _forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    function claimStrategyReward(address _strategy, address _reward, address _recipient, bool _forfeitRecentReward)
        external
        virtual
        nonReentrant
    {
        address rewardStreams = IBalanceForwarder(_strategy).balanceTrackerAddress();

        IRewardStreams(rewardStreams).claimReward(_strategy, _reward, _recipient, _forfeitRecentReward);
    }

    /// @notice Enables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can enable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the current account's balance
    function enableBalanceForwarder() external virtual nonReentrant {
        uint256 userBalance = IERC20(address(this)).balanceOf(msg.sender);

        _enableBalanceForwarder(msg.sender, userBalance);
    }

    /// @notice Disables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function disableBalanceForwarder() external virtual nonReentrant {
        _disableBalanceForwarder(msg.sender);
    }

    /// @notice Retrieve the address of rewards contract, tracking changes in account's balances
    /// @return The balance tracker address
    function balanceTrackerAddress() external view returns (address) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return address($.balanceTracker);
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function balanceForwarderEnabled(address _account) external view returns (bool) {
        return _balanceForwarderEnabled(_account);
    }

    function _enableBalanceForwarder(address _sender, uint256 _senderBalance) internal {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        IBalanceTracker balanceTrackerCached = IBalanceTracker($.balanceTracker);

        if (address(balanceTrackerCached) == address(0)) revert Errors.NotSupported();
        if ($.isBalanceForwarderEnabled[_sender]) revert Errors.AlreadyEnabled();

        $.isBalanceForwarderEnabled[_sender] = true;
        balanceTrackerCached.balanceTrackerHook(_sender, _senderBalance, false);

        emit Events.EnableBalanceForwarder(_sender);
    }

    /// @notice Disables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function _disableBalanceForwarder(address _sender) internal {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        IBalanceTracker balanceTrackerCached = IBalanceTracker($.balanceTracker);

        if (address(balanceTrackerCached) == address(0)) revert Errors.NotSupported();
        if (!$.isBalanceForwarderEnabled[_sender]) revert Errors.AlreadyDisabled();

        $.isBalanceForwarderEnabled[_sender] = false;
        balanceTrackerCached.balanceTrackerHook(_sender, 0, false);

        emit Events.DisableBalanceForwarder(_sender);
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function _balanceForwarderEnabled(address _account) internal view returns (bool) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return $.isBalanceForwarderEnabled[_account];
    }

    /// @notice Retrieve the address of rewards contract, tracking changes in account's balances
    /// @return The balance tracker address
    function _balanceTrackerAddress() internal view returns (address) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return address($.balanceTracker);
    }
}

contract Rewards is RewardsModule {}
