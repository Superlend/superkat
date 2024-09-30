// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {StorageLib as Storage, EulerEarnStorage} from "../lib/StorageLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";
import {ConstantsLib as Constants} from "../lib/ConstantsLib.sol";

/// @title FeeModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract FeeModule is Shared {
    /// @notice Set performance fee recipient address.
    /// @param _newFeeRecipient Recipient address.
    function setFeeRecipient(address _newFeeRecipient) external virtual nonReentrant {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        emit Events.SetFeeRecipient($.feeRecipient, _newFeeRecipient);

        $.feeRecipient = _newFeeRecipient;
    }

    /// @notice Set performance fee (1e18 == 100%).
    /// @param _newFee Fee rate.
    function setPerformanceFee(uint96 _newFee) external virtual nonReentrant {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        uint96 performanceFeeCached = $.performanceFee;

        require(_newFee <= Constants.MAX_PERFORMANCE_FEE, Errors.MaxPerformanceFeeExceeded());
        require($.feeRecipient != address(0), Errors.FeeRecipientNotSet());

        emit Events.SetPerformanceFee(performanceFeeCached, _newFee);

        $.performanceFee = _newFee;
    }

    /// @notice Get the performance fee config.
    /// @return Fee recipient.
    /// @return Fee percentage.
    function performanceFeeConfig() public view virtual nonReentrantView returns (address, uint96) {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        return ($.feeRecipient, $.performanceFee);
    }
}

contract Fee is FeeModule {
    constructor(IntegrationsParams memory _integrationsParams) Shared(_integrationsParams) {}
}
