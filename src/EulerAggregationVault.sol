// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEulerAggregationVault} from "./interface/IEulerAggregationVault.sol";
// contracts
import {
    Dispatch,
    StrategyModule,
    AggregationVaultModule,
    FeeModule,
    RewardsModule,
    HooksModule,
    StrategyModule,
    WithdrawalQueueModule,
    RebalanceModule
} from "./Dispatch.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin-upgradeable/utils/ContextUpgradeable.sol";
import {Shared} from "./common/Shared.sol";
// libs
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StorageLib as Storage, AggregationVaultStorage} from "./lib/StorageLib.sol";
import {AmountCap} from "./lib/AmountCapLib.sol";
import {ErrorsLib as Errors} from "./lib/ErrorsLib.sol";
import {ConstantsLib as Constants} from "./lib/ConstantsLib.sol";

/// @title EulerAggregationVault contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @dev inspired by Yearn v3 ❤️
contract EulerAggregationVault is Dispatch, AccessControlEnumerableUpgradeable, IEulerAggregationVault {
    using SafeCast for uint256;

    /// @dev Constructor.
    constructor(IEulerAggregationVault.ConstructorParams memory _constructorParams)
        Shared(_constructorParams.evc)
        Dispatch(
            _constructorParams.aggregationVaultModule,
            _constructorParams.rewardsModule,
            _constructorParams.hooksModule,
            _constructorParams.feeModule,
            _constructorParams.strategyModule,
            _constructorParams.rebalanceModule,
            _constructorParams.withdrawalQueueModule
        )
    {}

    /// @dev Initialize the EulerAggregationVault.
    /// @param _initParams InitParams struct.
    function init(IEulerAggregationVault.InitParams calldata _initParams) public initializer {
        __ERC4626_init_unchained(IERC20(_initParams.asset));
        __ERC20_init_unchained(_initParams.name, _initParams.symbol);
        __ERC20Votes_init_unchained();
        __AccessControlEnumerable_init_unchained();

        if (_initParams.initialCashAllocationPoints == 0) revert Errors.InitialAllocationPointsZero();

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.locked = Constants.REENTRANCYLOCK__UNLOCKED;
        $.balanceTracker = _initParams.balanceTracker;
        $.strategies[address(0)] = IEulerAggregationVault.Strategy({
            allocated: 0,
            allocationPoints: _initParams.initialCashAllocationPoints.toUint96(),
            status: IEulerAggregationVault.StrategyStatus.Active,
            cap: AmountCap.wrap(0)
        });
        $.totalAllocationPoints = _initParams.initialCashAllocationPoints;

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _initParams.aggregationVaultOwner);

        // Setup role admins
        _setRoleAdmin(Constants.GUARDIAN, Constants.GUARDIAN_ADMIN);
        _setRoleAdmin(Constants.STRATEGY_OPERATOR, Constants.STRATEGY_OPERATOR_ADMIN);
        _setRoleAdmin(Constants.AGGREGATION_VAULT_MANAGER, Constants.AGGREGATION_VAULT_MANAGER_ADMIN);
        _setRoleAdmin(Constants.WITHDRAWAL_QUEUE_MANAGER, Constants.WITHDRAWAL_QUEUE_MANAGER_ADMIN);
    }

    /// @dev See {FeeModule-setFeeRecipient}.
    function setFeeRecipient(address _newFeeRecipient)
        public
        override (IEulerAggregationVault, FeeModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(feeModule)
    {}

    /// @dev See {FeeModule-setPerformanceFee}.
    function setPerformanceFee(uint96 _newFee)
        public
        override (IEulerAggregationVault, FeeModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(feeModule)
    {}

    /// @dev See {RewardsModule-optInStrategyRewards}.
    function optInStrategyRewards(address _strategy)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-optOutStrategyRewards}.
    function optOutStrategyRewards(address _strategy)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-optOutStrategyRewards}.
    function enableRewardForStrategy(address _strategy, address _reward)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-disableRewardForStrategy}.
    function disableRewardForStrategy(address _strategy, address _reward, bool _forfeitRecentReward)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-claimStrategyReward}.
    function claimStrategyReward(address _strategy, address _reward, address _recipient, bool _forfeitRecentReward)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @dev See {HooksModule-setHooksConfig}.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns)
        public
        override (IEulerAggregationVault, HooksModule)
        onlyRole(Constants.AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(hooksModule)
    {}

    /// @dev See {StrategyModule-addStrategy}.
    function addStrategy(address _strategy, uint256 _allocationPoints)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(Constants.STRATEGY_OPERATOR)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @dev See {StrategyModule-removeStrategy}.
    function removeStrategy(address _strategy)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(Constants.STRATEGY_OPERATOR)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @dev See {StrategyModule-setStrategyCap}.
    function setStrategyCap(address _strategy, uint16 _cap)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(Constants.GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @dev See {StrategyModule-adjustAllocationPoints}.
    function adjustAllocationPoints(address _strategy, uint256 _newPoints)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(Constants.GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @dev See {StrategyModule-toggleStrategyEmergencyStatus}.
    function toggleStrategyEmergencyStatus(address _strategy)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(Constants.GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @dev See {RewardsModule-enableBalanceForwarder}.
    function enableBalanceForwarder() public override (IEulerAggregationVault, RewardsModule) use(rewardsModule) {}

    /// @dev See {RewardsModule-disableBalanceForwarder}.
    function disableBalanceForwarder() public override (IEulerAggregationVault, RewardsModule) use(rewardsModule) {}

    /// @dev See {RebalanceModule-rebalance}.
    function rebalance(address[] calldata _strategies)
        public
        override (IEulerAggregationVault, RebalanceModule)
        use(rebalanceModule)
    {}

    /// @dev See {WithdrawalQueue-reorderWithdrawalQueue}.
    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2)
        public
        override (IEulerAggregationVault, WithdrawalQueueModule)
        onlyRole(Constants.WITHDRAWAL_QUEUE_MANAGER)
        onlyEVCAccountOwner
        use(withdrawalQueueModule)
    {}

    /// @dev See {VaultModule-harvest}.
    function harvest() public override (IEulerAggregationVault, AggregationVaultModule) use(aggregationVaultModule) {}

    /// @dev See {VaultModule-updateInterestAccrued}.
    function updateInterestAccrued()
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
    {}

    /// @dev See {VaultModule-gulp}.
    function gulp() public override (IEulerAggregationVault, AggregationVaultModule) use(aggregationVaultModule) {}

    /// @dev See {VaultModule-deposit}.
    function deposit(uint256 _assets, address _receiver)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256)
    {}

    /// @dev See {VaultModule-mint}.
    function mint(uint256 _shares, address _receiver)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256)
    {}

    /// @dev See {VaultModule-withdraw}.
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256 shares)
    {}

    /// @dev See {VaultModule-redeem}.
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256 assets)
    {}

    /// @dev See {VaultModule-interestAccrued}.
    function interestAccrued()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.interestAccrued();
    }

    /// @dev See {VaultModule-getAggregationVaultSavingRate}.
    function getAggregationVaultSavingRate()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint40, uint40, uint168)
    {
        return super.getAggregationVaultSavingRate();
    }

    /// @dev See {VaultModule-totalAllocated}.
    function totalAllocated() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint256) {
        return super.totalAllocated();
    }

    /// @dev See {VaultModule-totalAssetsDeposited}.
    function totalAssetsDeposited()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.totalAssetsDeposited();
    }

    /// @dev See {VaultModule-lastHarvestTimestamp}.
    function lastHarvestTimestamp()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.lastHarvestTimestamp();
    }

    /// @dev See {VaultModule-totalAssetsAllocatable}.
    function totalAssetsAllocatable()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.totalAssetsAllocatable();
    }

    /// @dev See {VaultModule-totalAssets}.
    function totalAssets() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint256) {
        return super.totalAssets();
    }

    /// @dev See {VaultModule-convertToShares}.
    function convertToShares(uint256 _assets)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.convertToShares(_assets);
    }

    /// @dev See {VaultModule-convertToAssets}.
    function convertToAssets(uint256 _shares)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.convertToAssets(_shares);
    }

    /// @dev See {VaultModule-maxWithdraw}.
    function maxWithdraw(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxWithdraw(_owner);
    }

    /// @dev See {VaultModule-maxRedeem}.
    function maxRedeem(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxRedeem(_owner);
    }

    /// @dev See {VaultModule-previewDeposit}.
    function previewDeposit(uint256 _assets)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewDeposit(_assets);
    }

    /// @dev See {VaultModule-previewMint}.
    function previewMint(uint256 _shares)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewMint(_shares);
    }

    /// @dev See {VaultModule-previewWithdraw}.
    function previewWithdraw(uint256 _assets)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewWithdraw(_assets);
    }

    /// @dev See {VaultModule-previewRedeem}.
    function previewRedeem(uint256 _shares)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewRedeem(_shares);
    }

    /// @dev See {VaultModule-balanceOf}.
    function balanceOf(address _account)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.balanceOf(_account);
    }

    /// @dev See {VaultModule-totalSupply}.
    function totalSupply() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint256) {
        return super.totalSupply();
    }

    /// @dev See {VaultModule-decimals}.
    function decimals() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint8) {
        return super.decimals();
    }

    /// @dev See {VaultModule-maxDeposit}.
    function maxDeposit(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxDeposit(_owner);
    }

    /// @dev See {VaultModule-maxMint}.
    function maxMint(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxMint(_owner);
    }

    /// @dev See {StrategyModule-getStrategy}.
    function getStrategy(address _strategy)
        public
        view
        override (IEulerAggregationVault, StrategyModule)
        returns (IEulerAggregationVault.Strategy memory)
    {
        return super.getStrategy(_strategy);
    }

    /// @dev See {StrategyModule-totalAllocationPoints}.
    function totalAllocationPoints() public view override (IEulerAggregationVault, StrategyModule) returns (uint256) {
        return super.totalAllocationPoints();
    }

    /// @dev See {FeeModule-performanceFeeConfig}.
    function performanceFeeConfig()
        public
        view
        override (IEulerAggregationVault, FeeModule)
        returns (address, uint96)
    {
        return super.performanceFeeConfig();
    }

    /// @dev See {HooksModule-getHooksConfig}.
    function getHooksConfig() public view override (IEulerAggregationVault, HooksModule) returns (address, uint32) {
        return super.getHooksConfig();
    }

    /// @dev See {RewardsModule-balanceTrackerAddress}.
    function balanceTrackerAddress() public view override (IEulerAggregationVault, RewardsModule) returns (address) {
        return super.balanceTrackerAddress();
    }

    /// @dev See {RewardsModule-balanceForwarderEnabled}.
    function balanceForwarderEnabled(address _account)
        public
        view
        override (IEulerAggregationVault, RewardsModule)
        returns (bool)
    {
        return super.balanceForwarderEnabled(_account);
    }

    /// @dev See {WithdrawalQueueModule-withdrawalQueue}.
    function withdrawalQueue()
        public
        view
        override (IEulerAggregationVault, WithdrawalQueueModule)
        returns (address[] memory)
    {
        return super.withdrawalQueue();
    }

    /// @dev Overriding _msgSender().
    function _msgSender() internal view override (Dispatch, ContextUpgradeable) returns (address) {
        return Dispatch._msgSender();
    }
}
