// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {StorageLib as Storage, YieldAggregatorStorage} from "../lib/StorageLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {ConstantsLib as Constants} from "../lib/ConstantsLib.sol";

/// @title HooksModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract HooksModule is Shared {
    /// @notice Set hooks contract and hooked functions.
    /// @param _hooksTarget Hooks contract.
    /// @param _hookedFns Hooked functions.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns) external virtual nonReentrant {
        if (_hookedFns != 0 && _hooksTarget == address(0)) {
            revert Errors.InvalidHooksTarget();
        }
        if (_hooksTarget != address(0) && IHookTarget(_hooksTarget).isHookTarget() != IHookTarget.isHookTarget.selector)
        {
            revert Errors.NotHooksContract();
        }
        if (_hookedFns >= Constants.ACTIONS_COUNTER) revert Errors.InvalidHookedFns();

        YieldAggregatorStorage storage $ = Storage._getYieldAggregatorStorage();
        $.hooksTarget = _hooksTarget;
        $.hookedFns = _hookedFns;

        emit Events.SetHooksConfig(_hooksTarget, _hookedFns);
    }

    /// @notice Get the hooks contract and the hooked functions.
    /// @return Hooks contract.
    /// @return Hooked functions.
    function getHooksConfig() public view virtual nonReentrantView returns (address, uint32) {
        YieldAggregatorStorage storage $ = Storage._getYieldAggregatorStorage();

        return ($.hooksTarget, $.hookedFns);
    }
}

contract Hooks is HooksModule {
    constructor(address _evc) Shared(_evc) {}
}
