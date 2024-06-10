// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {HooksLib, HooksType} from "./lib/HooksLib.sol";
import {IHookTarget} from "./interface/IHookTarget.sol";

contract Hooks {
    using HooksLib for HooksType;

    error NotHooksContract();
    error InvalidHookedFns();

    uint32 public constant DEPOSIT = 1 << 0;
    uint32 public constant MINT = 1 << 1;
    uint32 public constant WITHDRAW = 1 << 2;
    uint32 public constant REDEEM = 1 << 3;
    uint32 public constant REBALANCE = 1 << 4;
    uint32 public constant HARVEST = 1 << 5;
    uint32 public constant GULP = 1 << 6;
    uint32 public constant REORDER_WITHDRAWAL_QUEUE = 1 << 7;
    uint32 public constant ADD_STRATEGY = 1 << 8;
    uint32 public constant REMOVE_STRATEGY = 1 << 9;

    uint32 constant ACTIONS_COUNTER = 1 << 10;

    address public hooksContract;
    HooksType public hookedFn;

    function setHookConfig(address _hooksContract, uint32 _hookedFns) external {
        if (
            _hooksContract != address(0)
                && IHookTarget(_hooksContract).isHookTarget() != IHookTarget.isHookTarget.selector
        ) revert NotHooksContract();

        if (_hookedFns >= ACTIONS_COUNTER) revert InvalidHookedFns();

        hooksContract = _hooksContract;
        hookedFn = HooksType.wrap(_hookedFns);
    }
}
