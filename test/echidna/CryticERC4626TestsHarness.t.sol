// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// echidna erc-4626 properties tests
import {CryticERC4626PropertyTests} from "crytic-properties/ERC4626/ERC4626PropertyTests.sol";
// contracts
import {EulerAggregationVault} from "../../src/EulerAggregationVault.sol";
import {Hooks} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {Rebalance} from "../../src/module/Rebalance.sol";
import {WithdrawalQueue} from "../../src/module/WithdrawalQueue.sol";
import {EulerAggregationVaultFactory} from "../../src/EulerAggregationVaultFactory.sol";
import {Strategy} from "../../src/module/Strategy.sol";
import {TestERC20Token} from "crytic-properties/ERC4626/util/TestERC20Token.sol";
// evc setup
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

contract CryticERC4626TestsHarness is CryticERC4626PropertyTests {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    EthereumVaultConnector public evc;
    address factoryDeployer;

    // core modules
    Rewards rewardsImpl;
    Hooks hooksImpl;
    Fee feeModuleImpl;
    Strategy strategyModuleImpl;
    Rebalance rebalanceModuleImpl;
    WithdrawalQueue withdrawalQueueModuleImpl;

    EulerAggregationVaultFactory eulerAggregationVaultFactory;
    EulerAggregationVault eulerAggregationVault;

    constructor() {
        evc = new EthereumVaultConnector();

        rewardsImpl = new Rewards(address(evc));
        hooksImpl = new Hooks(address(evc));
        feeModuleImpl = new Fee(address(evc));
        strategyModuleImpl = new Strategy(address(evc));
        rebalanceModuleImpl = new Rebalance(address(evc));
        withdrawalQueueModuleImpl = new WithdrawalQueue(address(evc));

        EulerAggregationVaultFactory.FactoryParams memory factoryParams = EulerAggregationVaultFactory.FactoryParams({
            owner: address(this),
            evc: address(evc),
            balanceTracker: address(0),
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            strategyModuleImpl: address(strategyModuleImpl),
            rebalanceModuleImpl: address(rebalanceModuleImpl),
            withdrawalQueueModuleImpl: address(withdrawalQueueModuleImpl)
        });
        eulerAggregationVaultFactory = new EulerAggregationVaultFactory(factoryParams);

        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        address _vault = eulerAggregationVaultFactory.deployEulerAggregationVault(
            address(_asset), "TT_Agg", "TT_Agg", CASH_RESERVE_ALLOCATION_POINTS
        );

        initialize(address(_vault), address(_asset), false);
    }
}
