// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Shared} from "../Shared.sol";
import {StorageLib, HooksStorage} from "../lib/StorageLib.sol";
import {HooksLib} from "../lib/HooksLib.sol";
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";

abstract contract HooksModule is Shared {
    using HooksLib for uint32;

    /// @notice Set hooks contract and hooked functions.
    /// @param _hooksTarget Hooks contract.
    /// @param _hookedFns Hooked functions.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns) external virtual nonReentrant {
        _setHooksConfig(_hooksTarget, _hookedFns);
    }

    /// @notice Get the hooks contract and the hooked functions.
    /// @return address Hooks contract.
    /// @return uint32 Hooked functions.
    function getHooksConfig() external view returns (address, uint32) {
        HooksStorage storage $ = StorageLib._getHooksStorage();

        return _getHooksConfig($.hooksConfig);
    }
}

contract Hooks is HooksModule {}
