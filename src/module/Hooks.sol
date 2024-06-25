// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
// contracts
import {Shared} from "../Shared.sol";
// libs
import {StorageLib, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {HooksLib} from "../lib/HooksLib.sol";
import {EventsLib} from "../lib/EventsLib.sol";

/// @title HooksModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract HooksModule is Shared {
    using HooksLib for uint32;

    /// @notice Set hooks contract and hooked functions.
    /// @param _hooksTarget Hooks contract.
    /// @param _hookedFns Hooked functions.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns) external virtual nonReentrant {
        _setHooksConfig(_hooksTarget, _hookedFns);

        emit EventsLib.SetHooksConfig(_hooksTarget, _hookedFns);
    }

    /// @notice Get the hooks contract and the hooked functions.
    /// @return address Hooks contract.
    /// @return uint32 Hooked functions.
    function getHooksConfig() external view returns (address, uint32) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return _getHooksConfig($.hooksConfig);
    }
}

contract Hooks is HooksModule {}
