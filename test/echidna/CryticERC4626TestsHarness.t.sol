// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// echidna erc-4626 properties tests
// Not importing CryticERC4626PropertyTests directly as we override here some of the property tests in CryticERC4626SenderIndependent
import {CryticERC4626RedeemUsingApproval} from "crytic-properties/ERC4626/properties/RedeemUsingApprovalProps.sol";
import {CryticERC4626MustNotRevert} from "crytic-properties/ERC4626/properties/MustNotRevertProps.sol";
import {CryticERC4626FunctionalAccounting} from "crytic-properties/ERC4626/properties/FunctionalAccountingProps.sol";
import {CryticERC4626Rounding} from "crytic-properties/ERC4626/properties/RoundingProps.sol";
import {CryticERC4626SecurityProps} from "crytic-properties/ERC4626/properties/SecurityProps.sol";
// contracts
import {YieldAggregator, Shared, IYieldAggregator} from "../../src/YieldAggregator.sol";
import {YieldAggregatorVault} from "../../src/module/YieldAggregatorVault.sol";
import {Hooks} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {WithdrawalQueue} from "../../src/module/WithdrawalQueue.sol";
import {YieldAggregatorFactory} from "../../src/YieldAggregatorFactory.sol";
import {Strategy} from "../../src/module/Strategy.sol";
import {TestERC20Token} from "crytic-properties/ERC4626/util/TestERC20Token.sol";
// evc setup
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

/// @dev Aggregator contract for various 4626 property tests.
/// @dev Inherit from this & echidna will test all properties at the same time.
contract CryticERC4626TestsHarness is
    CryticERC4626RedeemUsingApproval,
    CryticERC4626MustNotRevert,
    CryticERC4626FunctionalAccounting,
    CryticERC4626Rounding,
    CryticERC4626SecurityProps
{
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    EthereumVaultConnector public evc;
    Shared.IntegrationsParams integrationsParams;
    IYieldAggregator.DeploymentParams deploymentParams;
    address factoryDeployer;

    // core modules
    YieldAggregatorVault yieldAggregatorVaultModule;
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModule;
    Strategy strategyModule;
    WithdrawalQueue withdrawalQueueModule;

    YieldAggregatorFactory eulerYieldAggregatorVaultFactory;
    YieldAggregator eulerYieldAggregatorVault;

    constructor() {
        evc = new EthereumVaultConnector();

        integrationsParams =
            Shared.IntegrationsParams({evc: address(evc), balanceTracker: address(0), isHarvestCoolDownCheckOn: true});

        yieldAggregatorVaultModule = new YieldAggregatorVault(integrationsParams);
        rewardsModule = new Rewards(integrationsParams);
        hooksModule = new Hooks(integrationsParams);
        feeModule = new Fee(integrationsParams);
        strategyModule = new Strategy(integrationsParams);
        withdrawalQueueModule = new WithdrawalQueue(integrationsParams);

        deploymentParams = IYieldAggregator.DeploymentParams({
            yieldAggregatorVaultModule: address(yieldAggregatorVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModule),
            strategyModule: address(strategyModule),
            withdrawalQueueModule: address(withdrawalQueueModule)
        });
        address yieldAggregatorImpl = address(new YieldAggregator(integrationsParams, deploymentParams));

        eulerYieldAggregatorVaultFactory = new YieldAggregatorFactory(yieldAggregatorImpl);

        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        address _vault = eulerYieldAggregatorVaultFactory.deployYieldAggregator(
            address(_asset), "TT_Agg", "TT_Agg", CASH_RESERVE_ALLOCATION_POINTS
        );

        initialize(address(_vault), address(_asset), false);
    }

    /// @notice verify `maxDeposit()` assumes the receiver/sender has infinite assets
    function verify_maxDepositIgnoresSenderAssets(uint256 tokens) public {
        address receiver = address(this);
        uint256 maxDepositBefore = vault.maxDeposit(receiver);
        asset.mint(receiver, tokens);
        uint256 maxDepositAfter = vault.maxDeposit(receiver);
        assertEq(maxDepositBefore, maxDepositAfter, "maxDeposit must assume the agent has infinite assets");
    }

    /// @notice verify `maxMint()` assumes the receiver/sender has infinite assets
    function verify_maxMintIgnoresSenderAssets(uint256 tokens) public {
        address receiver = address(this);
        uint256 maxMintBefore = vault.maxMint(receiver);
        asset.mint(receiver, tokens);
        uint256 maxMintAfter = vault.maxMint(receiver);
        assertEq(maxMintBefore, maxMintAfter, "maxMint must assume the agent has infinite assets");
    }

    /// @notice verify `previewMint()` does not account for msg.sender asset balance
    function verify_previewMintIgnoresSender(uint256 tokens, uint256 shares) public {
        address receiver = address(this);
        uint256 assetsExpectedBefore = vault.previewMint(shares);
        prepareAddressForDeposit(receiver, tokens);

        uint256 assetsExpectedAfter = vault.previewMint(shares);
        assertEq(assetsExpectedBefore, assetsExpectedAfter, "previewMint must not be dependent on msg.sender");
    }

    /// @notice verify `previewDeposit()` does not account for msg.sender asset balance
    function verify_previewDepositIgnoresSender(uint256 tokens) public {
        address receiver = address(this);
        uint256 sharesExpectedBefore = vault.previewDeposit(tokens);
        prepareAddressForDeposit(receiver, tokens);

        uint256 sharesExpectedAfter = vault.previewDeposit(tokens);
        assertEq(sharesExpectedBefore, sharesExpectedAfter, "previewDeposit must not be dependent on msg.sender");
    }
}
