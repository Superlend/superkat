// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Base} from "./Base.sol";
import {HooksModule} from "./Hooks.sol";
import {RewardsModule} from "./Rewards.sol";

abstract contract Dispatch is RewardsModule, HooksModule {
    error E_Unauthorized();

    address public immutable MODULE_REWARDS;
    address public immutable MODULE_HOOKS;

    // /// @title DeployedModules
    // /// @notice This struct is used to pass in the addresses of EVault modules during deployment
    // struct DeployedModules {
    //     address initialize;
    //     address token;
    //     address vault;
    //     address borrowing;
    //     address liquidation;
    //     address riskManager;
    //     address balanceForwarder;
    //     address governance;
    // }

    // constructor(Integrations memory integrations, DeployedModules memory modules) Base(integrations) {
    //     MODULE_INITIALIZE = AddressUtils.checkContract(modules.initialize);
    //     MODULE_TOKEN = AddressUtils.checkContract(modules.token);
    //     MODULE_VAULT = AddressUtils.checkContract(modules.vault);
    //     MODULE_BORROWING = AddressUtils.checkContract(modules.borrowing);
    //     MODULE_LIQUIDATION = AddressUtils.checkContract(modules.liquidation);
    //     MODULE_RISKMANAGER = AddressUtils.checkContract(modules.riskManager);
    //     MODULE_BALANCE_FORWARDER = AddressUtils.checkContract(modules.balanceForwarder);
    //     MODULE_GOVERNANCE = AddressUtils.checkContract(modules.governance);
    // }
    constructor(address _rewardsModule, address _hooksModule) Base() {
        MODULE_REWARDS = _rewardsModule;
        MODULE_HOOKS = _hooksModule;
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
