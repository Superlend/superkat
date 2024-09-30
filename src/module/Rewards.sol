// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IBalanceForwarder} from "../interface/IBalanceForwarder.sol";
import {IEulerEarn} from "../interface/IEulerEarn.sol";
import {IBalanceTracker} from "reward-streams/src/interfaces/IBalanceTracker.sol";
import {IRewardStreams} from "reward-streams/src/interfaces/IRewardStreams.sol";
// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {StorageLib as Storage, EulerEarnStorage} from "../lib/StorageLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";

/// @title Rewards module
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A module to provide balancer tracking for reward streams and to integrate with strategies rewards.
/// @dev See https://github.com/euler-xyz/reward-streams.
abstract contract RewardsModule is IBalanceForwarder, Shared {
    /// @notice Opt in to strategy rewards.
    /// @param _strategy Strategy address.
    function optInStrategyRewards(address _strategy) external virtual nonReentrant {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        require($.strategies[_strategy].status == IEulerEarn.StrategyStatus.Active, Errors.StrategyShouldBeActive());

        IBalanceForwarder(_strategy).enableBalanceForwarder();

        emit Events.OptInStrategyRewards(_strategy);
    }

    /// @notice Opt out of strategy rewards
    /// @param _strategy Strategy address
    function optOutStrategyRewards(address _strategy) external virtual nonReentrant {
        IBalanceForwarder(_strategy).disableBalanceForwarder();

        emit Events.OptOutStrategyRewards(_strategy);
    }

    /// @notice Enable euler earn vault rewards for specific strategy's reward token.
    /// @param _strategy Strategy address.
    /// @param _reward Reward token address.
    function enableRewardForStrategy(address _strategy, address _reward) external virtual nonReentrant {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        require($.strategies[_strategy].status == IEulerEarn.StrategyStatus.Active, Errors.StrategyShouldBeActive());

        IRewardStreams(IBalanceForwarder(_strategy).balanceTrackerAddress()).enableReward(_strategy, _reward);

        emit Events.EnableRewardForStrategy(_strategy, _reward);
    }

    /// @notice Disable euler earn vault rewards for specific strategy's reward token.
    /// @param _strategy Strategy address.
    /// @param _reward Reward token address.
    /// @param _forfeitRecentReward Whether to forfeit the recent rewards or not.
    function disableRewardForStrategy(address _strategy, address _reward, bool _forfeitRecentReward)
        external
        virtual
        nonReentrant
    {
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

        emit Events.ClaimStrategyReward(_strategy, _reward, _recipient, _forfeitRecentReward);
    }

    /// @notice Enables balance forwarding for the authenticated account.
    /// @dev Only the authenticated account can enable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the current account's balance
    function enableBalanceForwarder() external virtual nonReentrant {
        uint256 userBalance = _balanceOf(_msgSender());

        _enableBalanceForwarder(_msgSender(), userBalance);
    }

    /// @notice Disables balance forwarding for the authenticated account.
    /// @dev Only the authenticated account can disable balance forwarding for itself.
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0.
    function disableBalanceForwarder() external virtual nonReentrant {
        _disableBalanceForwarder(_msgSender());
    }

    /// @notice Retrieve the address of rewards contract, tracking changes in account's balances.
    /// @return The balance tracker address.
    function balanceTrackerAddress() public view virtual nonReentrantView returns (address) {
        return balanceTracker;
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract.
    /// @param _account Address to query.
    /// @return True if balance forwarder is enabled.
    function balanceForwarderEnabled(address _account) public view virtual nonReentrantView returns (bool) {
        return _balanceForwarderEnabled(_account);
    }

    /// @dev Enables balance forwarding for the authenticated account.
    function _enableBalanceForwarder(address _sender, uint256 _senderBalance) internal {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        require(balanceTracker != address(0), Errors.EulerEarnRewardsNotSupported());
        bool wasBalanceForwarderEnabled = $.isBalanceForwarderEnabled[_sender];

        $.isBalanceForwarderEnabled[_sender] = true;
        IBalanceTracker(balanceTracker).balanceTrackerHook(_sender, _senderBalance, false);

        if (!wasBalanceForwarderEnabled) emit Events.EnableBalanceForwarder(_sender);
    }

    /// @notice Disables balance forwarding for the authenticated account.
    /// @dev Only the authenticated account can disable balance forwarding for itself.
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0.
    function _disableBalanceForwarder(address _sender) internal {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        require(balanceTracker != address(0), Errors.EulerEarnRewardsNotSupported());

        bool wasBalanceForwarderEnabled = $.isBalanceForwarderEnabled[_sender];

        $.isBalanceForwarderEnabled[_sender] = false;
        IBalanceTracker(balanceTracker).balanceTrackerHook(_sender, 0, false);

        if (wasBalanceForwarderEnabled) emit Events.DisableBalanceForwarder(_sender);
    }
}

contract Rewards is RewardsModule {
    constructor(IntegrationsParams memory _integrationsParams) Shared(_integrationsParams) {}
}
