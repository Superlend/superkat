// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {StorageLib as Storage, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";

/// @title FeeModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract FeeModule is Shared {
    /// @dev The maximum performanceFee the vault can have is 50%
    uint96 internal constant MAX_PERFORMANCE_FEE = 0.5e18;

    /// @notice Set performance fee recipient address
    /// @param _newFeeRecipient Recipient address
    function setFeeRecipient(address _newFeeRecipient) external virtual nonReentrant {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        emit Events.SetFeeRecipient($.feeRecipient, _newFeeRecipient);

        $.feeRecipient = _newFeeRecipient;
    }

    /// @notice Set performance fee (1e18 == 100%)
    /// @param _newFee Fee rate
    function setPerformanceFee(uint96 _newFee) external virtual nonReentrant {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        uint96 performanceFeeCached = $.performanceFee;

        if (_newFee > MAX_PERFORMANCE_FEE) revert Errors.MaxPerformanceFeeExceeded();
        if ($.feeRecipient == address(0)) revert Errors.FeeRecipientNotSet();

        emit Events.SetPerformanceFee(performanceFeeCached, _newFee);

        $.performanceFee = _newFee;
    }

    /// @notice Get the performance fee config.
    /// @return adddress Fee recipient.
    /// @return uint256 Fee percentage.
    function performanceFeeConfig() public view virtual nonReentrantView returns (address, uint96) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return ($.feeRecipient, $.performanceFee);
    }
}

contract Fee is FeeModule {
    constructor(address _evc) Shared(_evc) {}
}
