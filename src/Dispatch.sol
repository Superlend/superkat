// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Shared} from "./Shared.sol";
import {HooksModule} from "./modules/Hooks.sol";
import {RewardsModule} from "./modules/Rewards.sol";

abstract contract Dispatch is RewardsModule, HooksModule {
    error E_Unauthorized();

    address public immutable MODULE_REWARDS;
    address public immutable MODULE_HOOKS;
    address public immutable MODULE_FEE;
    address public immutable MODULE_ALLOCATION_POINTS;

    constructor(address _rewardsModule, address _hooksModule, address _feeModule, address _allocationPointsModule)
        Shared()
    {
        MODULE_REWARDS = _rewardsModule;
        MODULE_HOOKS = _hooksModule;
        MODULE_FEE = _feeModule;
        MODULE_ALLOCATION_POINTS = _allocationPointsModule;
    }

    // Modifier proxies the function call to a module and low-level returns the result
    modifier use(address module) {
        _; // when using the modifier, it is assumed the function body is empty.
        delegateToModule(module);
    }

    function delegateToModule(address module) private {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), module, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
