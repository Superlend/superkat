// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {StorageLib as Storage, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";

/// @title HooksModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract HooksModule is Shared {
    uint32 constant ACTIONS_COUNTER = 1 << 6;

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
        if (_hookedFns >= ACTIONS_COUNTER) revert Errors.InvalidHookedFns();

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.hooksTarget = _hooksTarget;
        $.hookedFns = _hookedFns;

        emit Events.SetHooksConfig(_hooksTarget, _hookedFns);
    }
}

contract Hooks is HooksModule {
    constructor(address _evc) Shared(_evc) {}
}
