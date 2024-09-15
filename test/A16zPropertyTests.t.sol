// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// a16z properties tests
import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
// contracts
import {YieldAggregator, Shared, IYieldAggregator} from "../src/YieldAggregator.sol";
import {YieldAggregatorVault} from "../src/module/YieldAggregatorVault.sol";
import {Hooks} from "../src/module/Hooks.sol";
import {Rewards} from "../src/module/Rewards.sol";
import {Fee} from "../src/module/Fee.sol";
import {WithdrawalQueue} from "../src/module/WithdrawalQueue.sol";
import {YieldAggregatorFactory} from "../src/YieldAggregatorFactory.sol";
import {Strategy} from "../src/module/Strategy.sol";
// mocks
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// evc setup
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

contract A16zPropertyTests is ERC4626Test {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    EthereumVaultConnector public evc;
    address public factoryOwner;

    Shared.IntegrationParams integrationParams;
    IYieldAggregator.DeploymentParams deploymentParams;

    // core modules
    YieldAggregatorVault yieldAggregatorVaultModule;
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModule;
    Strategy strategyModule;
    WithdrawalQueue withdrawalQueueModule;

    YieldAggregatorFactory eulerYieldAggregatorVaultFactory;
    YieldAggregator eulerYieldAggregatorVault;

    function setUp() public override {
        factoryOwner = makeAddr("FACTORY_OWNER");
        evc = new EthereumVaultConnector();

        integrationParams = Shared.IntegrationParams({evc: address(evc), isHarvestCoolDownCheckOn: true});

        yieldAggregatorVaultModule = new YieldAggregatorVault(integrationParams);
        rewardsModule = new Rewards(integrationParams);
        hooksModule = new Hooks(integrationParams);
        feeModule = new Fee(integrationParams);
        strategyModule = new Strategy(integrationParams);
        withdrawalQueueModule = new WithdrawalQueue(integrationParams);

        deploymentParams = IYieldAggregator.DeploymentParams({
            yieldAggregatorVaultModule: address(yieldAggregatorVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModule),
            strategyModule: address(strategyModule),
            withdrawalQueueModule: address(withdrawalQueueModule)
        });
        address yieldAggregatorImpl = address(new YieldAggregator(integrationParams, deploymentParams));

        eulerYieldAggregatorVaultFactory = new YieldAggregatorFactory(address(0), yieldAggregatorImpl);
        vm.prank(factoryOwner);

        _underlying_ = address(new ERC20Mock());
        _vault_ = eulerYieldAggregatorVaultFactory.deployYieldAggregator(
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
