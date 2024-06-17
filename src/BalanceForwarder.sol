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

    /// @custom:storage-location erc7201:euler_aggregation_vault.storage.BalanceForwarder
    struct BalanceForwarderStorage {
        IBalanceTracker balanceTracker;
        mapping(address => bool) isBalanceForwarderEnabled;
    }

    // keccak256(abi.encode(uint256(keccak256("euler_aggregation_vault.storage.BalanceForwarder")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BalanceForwarderStorageLocation =
        0xf0af7cc3986d6cac468ac54c07f5f08359b3a00d65f8e2a86f2676ec79073f00;


    event EnableBalanceForwarder(address indexed _user);
    event DisableBalanceForwarder(address indexed _user);

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
        BalanceForwarderStorage storage $ = _getBalanceForwarderStorage();

        return address($.balanceTracker);
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function balanceForwarderEnabled(address _account) external view returns (bool) {
        return _balanceForwarderEnabled(_account);
    }

    function _enableBalanceForwarder(address _sender, uint256 _senderBalance) internal {
        BalanceForwarderStorage storage $ = _getBalanceForwarderStorage();
        IBalanceTracker balanceTrackerCached = $.balanceTracker;

        if (address(balanceTrackerCached) == address(0)) revert NotSupported();
        if ($.isBalanceForwarderEnabled[_sender]) revert AlreadyEnabled();

        $.isBalanceForwarderEnabled[_sender] = true;
        balanceTrackerCached.balanceTrackerHook(_sender, _senderBalance, false);

        emit EnableBalanceForwarder(_sender);
    }

    /// @notice Disables balance forwarding for the authenticated account
    /// @dev Only the authenticated account can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function _disableBalanceForwarder(address _sender) internal {
        BalanceForwarderStorage storage $ = _getBalanceForwarderStorage();
        IBalanceTracker balanceTrackerCached = $.balanceTracker;
        
        if (address(balanceTrackerCached) == address(0)) revert NotSupported();
        if (!$.isBalanceForwarderEnabled[_sender]) revert AlreadyDisabled();

        $.isBalanceForwarderEnabled[_sender] = false;
        balanceTrackerCached.balanceTrackerHook(_sender, 0, false);

        emit DisableBalanceForwarder(_sender);
    }

    function _setBalanceTracker(address _balancerTracker) internal {
        BalanceForwarderStorage storage $ = _getBalanceForwarderStorage();

        $.balanceTracker = IBalanceTracker(_balancerTracker);
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function _balanceForwarderEnabled(address _account) internal view returns (bool) {
        BalanceForwarderStorage storage $ = _getBalanceForwarderStorage();

        return $.isBalanceForwarderEnabled[_account];
    }

    /// @notice Retrieve the address of rewards contract, tracking changes in account's balances
    /// @return The balance tracker address
    function _balanceTrackerAddress() internal view returns (address) {
        BalanceForwarderStorage storage $ = _getBalanceForwarderStorage();

        return address($.balanceTracker);
    }

    function _getBalanceForwarderStorage() private pure returns (BalanceForwarderStorage storage $) {
        assembly {
            $.slot := BalanceForwarderStorageLocation
        }
    }
}
