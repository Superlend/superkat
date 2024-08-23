// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

//contracts
import {AggregationVaultModule} from "./module/AggregationVault.sol";
import {HooksModule} from "./module/Hooks.sol";
import {RewardsModule} from "./module/Rewards.sol";
import {StrategyModule} from "./module/Strategy.sol";
import {FeeModule} from "./module/Fee.sol";
import {RebalanceModule} from "./module/Rebalance.sol";
import {WithdrawalQueueModule} from "./module/WithdrawalQueue.sol";
import {Shared} from "./common/Shared.sol";

/// @title Dispatch contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @dev This contract implement the modifier to use for forwarding calls to a specific module using delegateCall.
/// @dev Copied from https://github.com/euler-xyz/euler-vault-kit/blob/55d1a1fd7d572372f1c8b9f58aba0604bda3ca4f/src/EVault/Dispatch.sol.
abstract contract Dispatch is
    AggregationVaultModule,
    RewardsModule,
    HooksModule,
    FeeModule,
    StrategyModule,
    RebalanceModule,
    WithdrawalQueueModule
{
    address public immutable aggregationVaultModule;
    address public immutable rewardsModule;
    address public immutable hooksModule;
    address public immutable feeModule;
    address public immutable strategyModule;
    address public immutable rebalanceModule;
    address public immutable withdrawalQueueModule;

    /// @dev Constructor.
    /// @param _aggregationVaultModule Address of AggregationVault module.
    /// @param _rewardsModule Address of Rewards module.
    /// @param _hooksModule Address of Hooks module.
    /// @param _feeModule Address of Fee module.
    /// @param _strategyModule Address of Strategy module.
    /// @param _rebalanceModule Address of Rebalance module.
    constructor(
        address _aggregationVaultModule,
        address _rewardsModule,
        address _hooksModule,
        address _feeModule,
        address _strategyModule,
        address _rebalanceModule,
        address _withdrawalQueueModule
    ) {
        aggregationVaultModule = _aggregationVaultModule;
        rewardsModule = _rewardsModule;
        hooksModule = _hooksModule;
        feeModule = _feeModule;
        strategyModule = _strategyModule;
        rebalanceModule = _rebalanceModule;
        withdrawalQueueModule = _withdrawalQueueModule;
    }

    /// @dev Modifier proxies the function call to a module and low-level returns the result
    modifier use(address module) {
        _; // when using the modifier, it is assumed the function body is empty.
        _delegateToModule(module);
    }

    /// @dev forward the function call to a module and low-level returns the result
    function _delegateToModule(address module) private {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), module, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @dev Override for _msgSender() to use the EVC authentication.
    function _msgSender() internal view virtual override (AggregationVaultModule, Shared) returns (address) {
        return Shared._msgSender();
    }
}
