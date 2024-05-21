// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IBalanceForwarder} from "./interface/IBalanceForwarder.sol";

/// @title BalanceForwarderModule
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice An EVault module handling communication with a balance tracker contract.
abstract contract BalanceForwarder is IBalanceForwarder {
    error NotSupported();

    address public immutable balanceTracker;

    mapping(address => bool) internal isBalanceForwarderEnabled;

    constructor(address _balanceTracker) {
        balanceTracker = _balanceTracker;
    }

    /// @notice Retrieve the address of rewards contract, tracking changes in account's balances
    /// @return The balance tracker address
    function balanceTrackerAddress() external view returns (address) {
        return balanceTracker;
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function balanceForwarderEnabled(address _account) external view returns (bool) {
        return isBalanceForwarderEnabled[_account];
    }

    /// @notice Enables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can enable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the current account's balance
    function enableBalanceForwarder() external virtual {
        _enableBalanceForwarder(msg.sender);
    }

    /// @notice Disables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function disableBalanceForwarder() external virtual {
        _disableBalanceForwarder(msg.sender);
    }

    function _enableBalanceForwarder(address _sender) internal {
        if (balanceTracker == address(0)) revert NotSupported();

        // address account = EVCAuthenticate();
        // UserStorage storage user = vaultStorage.users[account];

        // bool wasBalanceForwarderEnabled = user.isBalanceForwarderEnabled();

        // user.setBalanceForwarder(true);
        // balanceTracker.balanceTrackerHook(account, user.getBalance().toUint(), false);

        // if (!wasBalanceForwarderEnabled) emit BalanceForwarderStatus(account, true);
    }

    /// @notice Disables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function _disableBalanceForwarder(address _sender) internal {
        if (balanceTracker == address(0)) revert NotSupported();

        // address account = EVCAuthenticate();
        // UserStorage storage user = vaultStorage.users[account];

        // bool wasBalanceForwarderEnabled = user.isBalanceForwarderEnabled();

        // user.setBalanceForwarder(false);
        // balanceTracker.balanceTrackerHook(account, 0, false);

        // if (wasBalanceForwarderEnabled) emit BalanceForwarderStatus(account, false);
    }
}
