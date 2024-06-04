// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IBalanceForwarder} from "./interface/IBalanceForwarder.sol";
import {IBalanceTracker} from "reward-streams/interfaces/IBalanceTracker.sol";

/// @title BalanceForwarder contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A generic contract to integrate with https://github.com/euler-xyz/reward-streams
abstract contract BalanceForwarder is IBalanceForwarder {
    error NotSupported();
    error AlreadyEnabled();
    error AlreadyDisabled();

    IBalanceTracker public immutable balanceTracker;

    mapping(address => bool) internal isBalanceForwarderEnabled;

    event EnableBalanceForwarder(address indexed _user);
    event DisableBalanceForwarder(address indexed _user);

    constructor(address _balanceTracker) {
        balanceTracker = IBalanceTracker(_balanceTracker);
    }

    /// @notice Enables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can enable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the current account's balance
    function enableBalanceForwarder() external virtual;

    /// @notice Disables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function disableBalanceForwarder() external virtual;

    /// @notice Retrieve the address of rewards contract, tracking changes in account's balances
    /// @return The balance tracker address
    function balanceTrackerAddress() external view returns (address) {
        return address(balanceTracker);
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function balanceForwarderEnabled(address _account) external view returns (bool) {
        return isBalanceForwarderEnabled[_account];
    }

    function _enableBalanceForwarder(address _sender, uint256 _senderBalance) internal {
        address cachedBalanceTracker = address(balanceTracker);

        if (cachedBalanceTracker == address(0)) revert NotSupported();
        if (isBalanceForwarderEnabled[_sender]) revert AlreadyEnabled();

        isBalanceForwarderEnabled[_sender] = true;
        IBalanceTracker(cachedBalanceTracker).balanceTrackerHook(_sender, _senderBalance, false);

        emit EnableBalanceForwarder(_sender);
    }

    /// @notice Disables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function _disableBalanceForwarder(address _sender) internal {
        address cachedBalanceTracker = address(balanceTracker);

        if (cachedBalanceTracker == address(0)) revert NotSupported();
        if (!isBalanceForwarderEnabled[_sender]) revert AlreadyDisabled();

        isBalanceForwarderEnabled[_sender] = false;
        IBalanceTracker(cachedBalanceTracker).balanceTrackerHook(_sender, 0, false);

        emit DisableBalanceForwarder(_sender);
    }
}
