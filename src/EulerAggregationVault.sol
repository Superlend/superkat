// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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
import {
    ERC20Upgradeable,
    ERC4626Upgradeable
} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin-upgradeable/utils/ContextUpgradeable.sol";
import {Shared} from "./common/Shared.sol";
// libs
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StorageLib as Storage, AggregationVaultStorage} from "./lib/StorageLib.sol";
import {AmountCap} from "./lib/AmountCapLib.sol";
import {ErrorsLib as Errors} from "./lib/ErrorsLib.sol";
import {EventsLib as Events} from "./lib/EventsLib.sol";

/// @title EulerAggregationVault contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @dev inspired by Yearn v3 ❤️
contract EulerAggregationVault is Dispatch, AccessControlEnumerableUpgradeable, IEulerAggregationVault {
    using SafeCast for uint256;

    // Roles and their ADMIN roles.
    // GUARDIAN: can set strategy cap, adjust strategy allocation points, set strategy status to EMERGENCY or revert it back.
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");
    bytes32 public constant GUARDIAN_ADMIN = keccak256("GUARDIAN_ADMIN");
    // STRATEGY_OPERATOR: can add and remove strategy.
    bytes32 public constant STRATEGY_OPERATOR = keccak256("STRATEGY_OPERATOR");
    bytes32 public constant STRATEGY_OPERATOR_ADMIN = keccak256("STRATEGY_OPERATOR_ADMIN");
    // AGGREGATION_VAULT_MANAGER: can set performance fee and recipient, opt in&out underlying strategy rewards,
    // including enabling, disabling and claiming those rewards, plus set hooks config.
    bytes32 public constant AGGREGATION_VAULT_MANAGER = keccak256("AGGREGATION_VAULT_MANAGER");
    bytes32 public constant AGGREGATION_VAULT_MANAGER_ADMIN = keccak256("AGGREGATION_VAULT_MANAGER_ADMIN");
    // WITHDRAWAL_QUEUE_MANAGER: can re-order withdrawal queue array.
    bytes32 public constant WITHDRAWAL_QUEUE_MANAGER = keccak256("WITHDRAWAL_QUEUE_MANAGER");
    bytes32 public constant WITHDRAWAL_QUEUE_MANAGER_ADMIN = keccak256("WITHDRAWAL_QUEUE_MANAGER_ADMIN");

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

    /// @notice Initialize the EulerAggregationVault.
    /// @param _initParams InitParams struct.
    function init(IEulerAggregationVault.InitParams calldata _initParams) public initializer {
        __ERC4626_init_unchained(IERC20(_initParams.asset));
        __ERC20_init_unchained(_initParams.name, _initParams.symbol);
        __ERC20Votes_init_unchained();
        __AccessControlEnumerable_init_unchained();

        if (_initParams.initialCashAllocationPoints == 0) revert Errors.InitialAllocationPointsZero();

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.locked = REENTRANCYLOCK__UNLOCKED;
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
        _setRoleAdmin(GUARDIAN, GUARDIAN_ADMIN);
        _setRoleAdmin(STRATEGY_OPERATOR, STRATEGY_OPERATOR_ADMIN);
        _setRoleAdmin(AGGREGATION_VAULT_MANAGER, AGGREGATION_VAULT_MANAGER_ADMIN);
        _setRoleAdmin(WITHDRAWAL_QUEUE_MANAGER, WITHDRAWAL_QUEUE_MANAGER_ADMIN);
    }

    /// @notice See {FeeModule-setFeeRecipient}.
    function setFeeRecipient(address _newFeeRecipient)
        public
        override (IEulerAggregationVault, FeeModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(feeModule)
    {}

    /// @notice See {FeeModule-setPerformanceFee}.
    function setPerformanceFee(uint96 _newFee)
        public
        override (IEulerAggregationVault, FeeModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(feeModule)
    {}

    /// @notice See {RewardsModule-optInStrategyRewards}.
    function optInStrategyRewards(address _strategy)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-optOutStrategyRewards}.
    function optOutStrategyRewards(address _strategy)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-optOutStrategyRewards}.
    function enableRewardForStrategy(address _strategy, address _reward)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-disableRewardForStrategy}.
    function disableRewardForStrategy(address _strategy, address _reward, bool _forfeitRecentReward)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-claimStrategyReward}.
    function claimStrategyReward(address _strategy, address _reward, address _recipient, bool _forfeitRecentReward)
        public
        override (IEulerAggregationVault, RewardsModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {HooksModule-setHooksConfig}.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns)
        public
        override (IEulerAggregationVault, HooksModule)
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(hooksModule)
    {}

    /// @notice See {StrategyModule-addStrategy}.
    function addStrategy(address _strategy, uint256 _allocationPoints)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(STRATEGY_OPERATOR)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-removeStrategy}.
    function removeStrategy(address _strategy)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(STRATEGY_OPERATOR)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-setStrategyCap}.
    function setStrategyCap(address _strategy, uint16 _cap)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-adjustAllocationPoints}.
    function adjustAllocationPoints(address _strategy, uint256 _newPoints)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-toggleStrategyEmergencyStatus}.
    function toggleStrategyEmergencyStatus(address _strategy)
        public
        override (IEulerAggregationVault, StrategyModule)
        onlyRole(GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {RewardsModule-enableBalanceForwarder}.
    function enableBalanceForwarder() public override (IEulerAggregationVault, RewardsModule) use(rewardsModule) {}

    /// @notice See {RewardsModule-disableBalanceForwarder}.
    function disableBalanceForwarder() public override (IEulerAggregationVault, RewardsModule) use(rewardsModule) {}

    /// @notice See {RebalanceModule-rebalance}.
    function rebalance(address[] calldata _strategies)
        public
        override (IEulerAggregationVault, RebalanceModule)
        use(rebalanceModule)
    {}

    /// @notice See {WithdrawalQueue-reorderWithdrawalQueue}.
    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2)
        public
        override (IEulerAggregationVault, WithdrawalQueueModule)
        onlyRole(WITHDRAWAL_QUEUE_MANAGER)
        onlyEVCAccountOwner
        use(withdrawalQueueModule)
    {}

    /// @notice See {VaultModule-harvest}.
    function harvest() public override (IEulerAggregationVault, AggregationVaultModule) use(aggregationVaultModule) {}

    /// @notice See {VaultModule-updateInterestAccrued}.
    function updateInterestAccrued()
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
    {}

    /// @notice See {VaultModule-gulp}.
    function gulp() public override (IEulerAggregationVault, AggregationVaultModule) use(aggregationVaultModule) {}

    /// @notice See {VaultModule-deposit}.
    function deposit(uint256 _assets, address _receiver)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256)
    {}

    /// @notice See {VaultModule-mint}.
    function mint(uint256 _shares, address _receiver)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256)
    {}

    /// @notice See {VaultModule-withdraw}.
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256 shares)
    {}

    /// @notice See {VaultModule-redeem}.
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        override (IEulerAggregationVault, AggregationVaultModule)
        use(aggregationVaultModule)
        returns (uint256 assets)
    {}

    /// @notice Return the accrued interest
    /// @return uint256 accrued interest
    function interestAccrued()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.interestAccrued();
    }

    /// @notice Get saving rate data.
    /// @return uint40 last interest update timestamp.
    /// @return uint40 timestamp when interest smearing end.
    /// @return uint168 Amount of interest left to distribute.
    function getAggregationVaultSavingRate()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint40, uint40, uint168)
    {
        return super.getAggregationVaultSavingRate();
    }

    /// @notice Get the total allocated amount.
    /// @return uint256 Total allocated.
    function totalAllocated() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint256) {
        return super.totalAllocated();
    }

    /// @notice Get the total assets deposited into the aggregation vault.
    /// @return uint256 Total assets deposited.
    function totalAssetsDeposited()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.totalAssetsDeposited();
    }

    /// @notice Get the latest harvest timestamp.
    /// @return uint256 Latest harvest timestamp.
    function lastHarvestTimestamp()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.lastHarvestTimestamp();
    }

    /// @notice get the total assets allocatable
    /// @dev the total assets allocatable is the amount of assets deposited into the aggregator + assets already deposited into strategies
    /// @return uint256 total assets
    function totalAssetsAllocatable()
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.totalAssetsAllocatable();
    }

    /// @notice Return the total amount of assets deposited, plus the accrued interest.
    /// @return uint256 total amount
    function totalAssets() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint256) {
        return super.totalAssets();
    }

    /// @dev See {IERC4626-convertToShares}.
    function convertToShares(uint256 _assets)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.convertToShares(_assets);
    }

    /// @dev See {IERC4626-convertToAssets}.
    function convertToAssets(uint256 _shares)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.convertToAssets(_shares);
    }

    /// @dev See {IERC4626-maxWithdraw}.
    function maxWithdraw(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxWithdraw(_owner);
    }

    /// @dev See {IERC4626-maxRedeem}.
    function maxRedeem(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxRedeem(_owner);
    }

    /// @dev See {IERC4626-previewDeposit}.
    function previewDeposit(uint256 _assets)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewDeposit(_assets);
    }

    /// @dev See {IERC4626-previewMint}.
    function previewMint(uint256 _shares)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewMint(_shares);
    }

    /// @dev See {IERC4626-previewWithdraw}.
    function previewWithdraw(uint256 _assets)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewWithdraw(_assets);
    }

    /// @dev See {IERC4626-previewRedeem}.
    function previewRedeem(uint256 _shares)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.previewRedeem(_shares);
    }

    function balanceOf(address _account)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.balanceOf(_account);
    }

    function totalSupply() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint256) {
        return super.totalSupply();
    }

    /// @dev See {IERC20Metadata-decimals}.
    function decimals() public view override (IEulerAggregationVault, AggregationVaultModule) returns (uint8) {
        return super.decimals();
    }

    function maxDeposit(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxDeposit(_owner);
    }

    /**
     * @dev See {IERC4626-maxMint}.
     */
    function maxMint(address _owner)
        public
        view
        override (IEulerAggregationVault, AggregationVaultModule)
        returns (uint256)
    {
        return super.maxMint(_owner);
    }

    /// @notice Get strategy params.
    /// @param _strategy strategy's address
    /// @return Strategy struct
    function getStrategy(address _strategy)
        public
        view
        override (IEulerAggregationVault, StrategyModule)
        returns (IEulerAggregationVault.Strategy memory)
    {
        return super.getStrategy(_strategy);
    }

    /// @notice Get the total allocation points.
    /// @return uint256 Total allocation points.
    function totalAllocationPoints() public view override (IEulerAggregationVault, StrategyModule) returns (uint256) {
        return super.totalAllocationPoints();
    }

    /// @notice Get the performance fee config.
    /// @return adddress Fee recipient.
    /// @return uint256 Fee percentage.
    function performanceFeeConfig()
        public
        view
        override (IEulerAggregationVault, FeeModule)
        returns (address, uint96)
    {
        return super.performanceFeeConfig();
    }

    /// @notice Get the hooks contract and the hooked functions.
    /// @return address Hooks contract.
    /// @return uint32 Hooked functions.
    function getHooksConfig() public view override (IEulerAggregationVault, HooksModule) returns (address, uint32) {
        return super.getHooksConfig();
    }

    /// @notice Retrieve the address of rewards contract, tracking changes in account's balances
    /// @return The balance tracker address
    function balanceTrackerAddress() public view override (IEulerAggregationVault, RewardsModule) returns (address) {
        return super.balanceTrackerAddress();
    }

    /// @notice Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function balanceForwarderEnabled(address _account)
        public
        view
        override (IEulerAggregationVault, RewardsModule)
        returns (bool)
    {
        return super.balanceForwarderEnabled(_account);
    }

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
