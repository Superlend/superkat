// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// a16z properties tests
import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
// contracts
import {EulerEarn, Shared, IEulerEarn} from "../src/EulerEarn.sol";
import {EulerEarnVault} from "../src/module/EulerEarnVault.sol";
import {Hooks} from "../src/module/Hooks.sol";
import {Rewards} from "../src/module/Rewards.sol";
import {Fee} from "../src/module/Fee.sol";
import {WithdrawalQueue} from "../src/module/WithdrawalQueue.sol";
import {EulerEarnFactory} from "../src/EulerEarnFactory.sol";
import {Strategy} from "../src/module/Strategy.sol";
// mocks
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// evc setup
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

contract A16zPropertyTests is ERC4626Test {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    EthereumVaultConnector public evc;
    address public factoryOwner;

    Shared.IntegrationsParams integrationsParams;
    IEulerEarn.DeploymentParams deploymentParams;

    // core modules
    EulerEarnVault eulerEarnVaultModule;
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModule;
    Strategy strategyModule;
    WithdrawalQueue withdrawalQueueModule;

    EulerEarnFactory eulerEulerEarnVaultFactory;
    EulerEarn eulerEulerEarnVault;

    function setUp() public override {
        factoryOwner = makeAddr("FACTORY_OWNER");
        evc = new EthereumVaultConnector();

        integrationsParams = Shared.IntegrationsParams({
            evc: address(evc),
            balanceTracker: address(0),
            permit2: address(0),
            isHarvestCoolDownCheckOn: true
        });

        eulerEarnVaultModule = new EulerEarnVault(integrationsParams);
        rewardsModule = new Rewards(integrationsParams);
        hooksModule = new Hooks(integrationsParams);
        feeModule = new Fee(integrationsParams);
        strategyModule = new Strategy(integrationsParams);
        withdrawalQueueModule = new WithdrawalQueue(integrationsParams);

        deploymentParams = IEulerEarn.DeploymentParams({
            eulerEarnVaultModule: address(eulerEarnVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModule),
            strategyModule: address(strategyModule),
            withdrawalQueueModule: address(withdrawalQueueModule)
        });
        address eulerEarnImpl = address(new EulerEarn(integrationsParams, deploymentParams));

        eulerEulerEarnVaultFactory = new EulerEarnFactory(eulerEarnImpl);
        vm.prank(factoryOwner);

        _underlying_ = address(new ERC20Mock());
        _vault_ = eulerEulerEarnVaultFactory.deployEulerEarn(
            _underlying_, "E20M_Agg", "E20M_Agg", CASH_RESERVE_ALLOCATION_POINTS
        );
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }

    function testToAvoidCoverage() public pure {
        return;
    }
}
