// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {HooksLib, HooksType} from "./lib/HooksLib.sol";
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";

abstract contract Hooks {
    using HooksLib for HooksType;

    error InvalidHooksTarget();
    error NotHooksContract();
    error InvalidHookedFns();
    error EmptyError();

    uint32 public constant DEPOSIT = 1 << 0;
    uint32 public constant WITHDRAW = 1 << 1;
    uint32 public constant REBALANCE = 1 << 2;
    uint32 public constant ADD_STRATEGY = 1 << 3;
    uint32 public constant REMOVE_STRATEGY = 1 << 4;

    uint32 constant ACTIONS_COUNTER = 1 << 5;

    /// @dev Contract with hooks implementation
    address public hookTarget;
    /// @dev Hooked functions
    HooksType public hookedFns;

    /// @notice Get the hooks contract and the hooked functions.
    /// @return address Hooks contract.
    /// @return uint32 Hooked functions.
    function getHooksConfig() external view returns (address, uint32) {
        return (hookTarget, hookedFns.toUint32());
    }

    /// @notice Set hooks contract and hooked functions.
    /// @dev This funtion should be overriden to implement access control.
    /// @param _hookTarget Hooks contract.
    /// @param _hookedFns Hooked functions.
    function setHooksConfig(address _hookTarget, uint32 _hookedFns) public virtual {
        if (_hookTarget != address(0) && IHookTarget(_hookTarget).isHookTarget() != IHookTarget.isHookTarget.selector) {
            revert NotHooksContract();
        }
        if (_hookedFns != 0 && _hookTarget == address(0)) {
            revert InvalidHooksTarget();
        }
        if (_hookedFns >= ACTIONS_COUNTER) revert InvalidHookedFns();

        hookTarget = _hookTarget;
        hookedFns = HooksType.wrap(_hookedFns);
    }

    /// @notice Checks whether a hook has been installed for the function and if so, invokes the hook target.
    /// @param _fn Function to check hook for.
    /// @param _caller Caller's address.
    function _callHookTarget(uint32 _fn, address _caller) internal {
        if (hookedFns.isNotSet(_fn)) return;

        address target = hookTarget;

        (bool success, bytes memory data) = target.call(abi.encodePacked(msg.data, _caller));

        if (!success) _revertBytes(data);
    }

    /// @dev Revert with call error or EmptyError
    /// @param _errorMsg call revert message
    function _revertBytes(bytes memory _errorMsg) private pure {
        if (_errorMsg.length > 0) {
            assembly {
                revert(add(32, _errorMsg), mload(_errorMsg))
            }
        }

        revert EmptyError();
    }
}
