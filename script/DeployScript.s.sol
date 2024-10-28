// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {EulerEarn, IEulerEarn, Shared} from "../../src/EulerEarn.sol";
import {EulerEarnVault} from "../../src/module/EulerEarnVault.sol";
import {Hooks, HooksModule} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {WithdrawalQueue} from "../../src/module/WithdrawalQueue.sol";
import {EulerEarnFactory} from "../../src/EulerEarnFactory.sol";
import {Strategy} from "../../src/module/Strategy.sol";

contract DeployScript is Script {
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
        // load ENV vars
        uint256 deployerKey = vm.envUint("DEPLOYMENT_DEPLOYER_PK");
        address deployerAddress = vm.rememberKey(deployerKey);

        address evc = vm.envAddress("DEPLOYMENT_EVC");
        address balanceTracker = vm.envAddress("DEPLOYMENT_BALANCE_TRACKER");
        address permit2 = vm.envAddress("DEPLOYMENT_PERMIT2");
        bool isHarvestCoolDownCheckOn = vm.envBool("DEPLOYMENT_IS_HARVEST_COOLDOWN_CHECK_ON");

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
