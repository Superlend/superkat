// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {HooksLib, HooksType} from "./lib/HooksLib.sol";
import {IHookTarget} from "./interface/IHookTarget.sol";

abstract contract Hooks {
    using HooksLib for HooksType;

    error NotHooksContract();
    error InvalidHookedFns();
    error EmptyError();

    uint32 public constant DEPOSIT = 1 << 0;
    uint32 public constant WITHDRAW = 1 << 1;
    uint32 public constant REBALANCE = 1 << 2;
    uint32 public constant ADD_STRATEGY = 1 << 3;
    uint32 public constant REMOVE_STRATEGY = 1 << 4;

    uint32 constant ACTIONS_COUNTER = 1 << 5;

    address public hooksTarget;
    HooksType public hookedFn;

    function setHooksConfig(address _hooksTarget, uint32 _hookedFns) public virtual {
        if (_hooksTarget != address(0) && IHookTarget(_hooksTarget).isHookTarget() != IHookTarget.isHookTarget.selector)
        {
            revert NotHooksContract();
        }

        if (_hookedFns >= ACTIONS_COUNTER) revert InvalidHookedFns();

        hooksTarget = _hooksTarget;
        hookedFn = HooksType.wrap(_hookedFns);
    }

    // Checks whether a hook has been installed for the _operation and if so, invokes the hook target.
    // If the hook target is zero address, this will revert.
    function _callHook(uint32 _operation, address _caller) internal {
        if (hookedFn.isNotSet(_operation)) return;

        address target = hooksTarget;

        // if (hookTarget == address(0)) revert E_OperationDisabled();

        (bool success, bytes memory data) = target.call(abi.encodePacked(msg.data, _caller));

        if (!success) _revertBytes(data);
    }

    function _revertBytes(bytes memory _errorMsg) private pure {
        if (_errorMsg.length > 0) {
            assembly {
                revert(add(32, _errorMsg), mload(_errorMsg))
            }
        }

        revert EmptyError();
    }
}
