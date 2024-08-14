// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// a16z properties tests
import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
// contracts
import {EulerAggregationVault} from "../src/EulerAggregationVault.sol";
import {Hooks} from "../src/module/Hooks.sol";
import {Rewards} from "../src/module/Rewards.sol";
import {Fee} from "../src/module/Fee.sol";
import {Rebalance} from "../src/module/Rebalance.sol";
import {WithdrawalQueue} from "../src/module/WithdrawalQueue.sol";
import {EulerAggregationVaultFactory} from "../src/EulerAggregationVaultFactory.sol";
import {Strategy} from "../src/module/Strategy.sol";
// mocks
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// evc setup
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

contract A16zPropertyTests is ERC4626Test {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    EthereumVaultConnector public evc;
    address public factoryOwner;

    // core modules
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModuleModule;
    Strategy strategyModuleModule;
    Rebalance rebalanceModuleModule;
    WithdrawalQueue withdrawalQueueModuleModule;

    EulerAggregationVaultFactory eulerAggregationVaultFactory;
    EulerAggregationVault eulerAggregationVault;

    function setUp() public override {
        factoryOwner = makeAddr("FACTORY_OWNER");
        evc = new EthereumVaultConnector();

        rewardsModule = new Rewards(address(evc));
        hooksModule = new Hooks(address(evc));
        feeModuleModule = new Fee(address(evc));
        strategyModuleModule = new Strategy(address(evc));
        rebalanceModuleModule = new Rebalance(address(evc));
        withdrawalQueueModuleModule = new WithdrawalQueue(address(evc));

        EulerAggregationVaultFactory.FactoryParams memory factoryParams = EulerAggregationVaultFactory.FactoryParams({
            owner: factoryOwner,
            evc: address(evc),
            balanceTracker: address(0),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModuleModule),
            strategyModule: address(strategyModuleModule),
            rebalanceModule: address(rebalanceModuleModule),
            withdrawalQueueModule: address(withdrawalQueueModuleModule)
        });
        eulerAggregationVaultFactory = new EulerAggregationVaultFactory(factoryParams);
        vm.prank(factoryOwner);

        _underlying_ = address(new ERC20Mock());
        _vault_ = eulerAggregationVaultFactory.deployEulerAggregationVault(
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
