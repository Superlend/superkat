// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerEarn, IEulerEarn, Shared} from "../src/EulerEarn.sol";
import {EulerEarnVault} from "../src/module/EulerEarnVault.sol";
import {Hooks, HooksModule} from "../src/module/Hooks.sol";
import {Rewards} from "../src/module/Rewards.sol";
import {Fee} from "../src/module/Fee.sol";
import {WithdrawalQueue} from "../src/module/WithdrawalQueue.sol";
import {EulerEarnFactory} from "../src/EulerEarnFactory.sol";
import {Strategy} from "../src/module/Strategy.sol";

/// @title Script to deploy Euler Earn protocol.
contract DeployProtocol is ScriptUtil {
    /// @dev core modules.
    EulerEarnVault eulerEarnVaultModule;
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModule;
    Strategy strategyModule;
    WithdrawalQueue withdrawalQueueModule;

    /// @dev EulerEarn implementation address.
    address eulerEarnImpl;
    /// @dev EulerEarnFactory contract.
    EulerEarnFactory eulerEulerEarnFactory;

    function run() public {
        // load JSON file
        string memory inputScriptFileName = "DeployProtocol_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        uint256 deployerKey = vm.parseJsonUint(json, "deployerKey");
        address deployerAddress = vm.rememberKey(deployerKey);

        address evc = vm.parseJsonAddress(json, "evc");
        address balanceTracker = vm.parseJsonAddress(json, "balanceTracker");
        address permit2 = vm.parseJsonAddress(json, "permit2");
        bool isHarvestCoolDownCheckOn = vm.parseJsonBool(json, "isHarvestCoolDownCheckOn");

        vm.startBroadcast(deployerAddress);

        Shared.IntegrationsParams memory integrationsParams = Shared.IntegrationsParams({
            evc: evc,
            balanceTracker: balanceTracker,
            permit2: permit2,
            isHarvestCoolDownCheckOn: isHarvestCoolDownCheckOn
        });

        // deploy core modules
        eulerEarnVaultModule = new EulerEarnVault(integrationsParams);
        rewardsModule = new Rewards(integrationsParams);
        hooksModule = new Hooks(integrationsParams);
        feeModule = new Fee(integrationsParams);
        strategyModule = new Strategy(integrationsParams);
        withdrawalQueueModule = new WithdrawalQueue(integrationsParams);

        // deploy EulerEarn implementation
        IEulerEarn.DeploymentParams memory deploymentParams = IEulerEarn.DeploymentParams({
            eulerEarnVaultModule: address(eulerEarnVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModule),
            strategyModule: address(strategyModule),
            withdrawalQueueModule: address(withdrawalQueueModule)
        });
        eulerEarnImpl = address(new EulerEarn(integrationsParams, deploymentParams));

        // deploy EulerEarnFactory
        eulerEulerEarnFactory = new EulerEarnFactory(eulerEarnImpl);

        vm.stopBroadcast();
    }
}
