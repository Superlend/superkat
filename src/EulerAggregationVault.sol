// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEulerAggregationVault} from "./interface/IEulerAggregationVault.sol";
// contracts
import {Dispatch} from "./Dispatch.sol";
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
contract EulerAggregationVault is Dispatch, AccessControlEnumerableUpgradeable {
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
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(feeModule)
    {}

    /// @notice See {FeeModule-setPerformanceFee}.
    function setPerformanceFee(uint96 _newFee)
        public
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(feeModule)
    {}

    /// @notice See {RewardsModule-optInStrategyRewards}.
    function optInStrategyRewards(address _strategy)
        public
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-optOutStrategyRewards}.
    function optOutStrategyRewards(address _strategy)
        public
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-optOutStrategyRewards}.
    function enableRewardForStrategy(address _strategy, address _reward)
        public
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-disableRewardForStrategy}.
    function disableRewardForStrategy(address _strategy, address _reward, bool _forfeitRecentReward)
        public
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {RewardsModule-claimStrategyReward}.
    function claimStrategyReward(address _strategy, address _reward, address _recipient, bool _forfeitRecentReward)
        public
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(rewardsModule)
    {}

    /// @notice See {HooksModule-setHooksConfig}.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns)
        public
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        onlyEVCAccountOwner
        use(hooksModule)
    {}

    /// @notice See {StrategyModule-addStrategy}.
    function addStrategy(address _strategy, uint256 _allocationPoints)
        public
        override
        onlyRole(STRATEGY_OPERATOR)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-removeStrategy}.
    function removeStrategy(address _strategy)
        public
        override
        onlyRole(STRATEGY_OPERATOR)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-setStrategyCap}.
    function setStrategyCap(address _strategy, uint16 _cap)
        public
        override
        onlyRole(GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-adjustAllocationPoints}.
    function adjustAllocationPoints(address _strategy, uint256 _newPoints)
        public
        override
        onlyRole(GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {StrategyModule-toggleStrategyEmergencyStatus}.
    function toggleStrategyEmergencyStatus(address _strategy)
        public
        override
        onlyRole(GUARDIAN)
        onlyEVCAccountOwner
        use(strategyModule)
    {}

    /// @notice See {RewardsModule-enableBalanceForwarder}.
    function enableBalanceForwarder() public override use(rewardsModule) {}

    /// @notice See {RewardsModule-disableBalanceForwarder}.
    function disableBalanceForwarder() public override use(rewardsModule) {}

    /// @notice See {RebalanceModule-rebalance}.
    function rebalance(address[] calldata _strategies) public override use(rebalanceModule) {}

    /// @notice See {WithdrawalQueue-reorderWithdrawalQueue}.
    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2)
        public
        override
        onlyRole(WITHDRAWAL_QUEUE_MANAGER)
        onlyEVCAccountOwner
        use(withdrawalQueueModule)
    {}

    /// @notice See {VaultModule-harvest}.
    function harvest() public override use(aggregationVaultModule) {}

    /// @notice See {VaultModule-updateInterestAccrued}.
    function updateInterestAccrued() public override use(aggregationVaultModule) {}

    /// @notice See {VaultModule-gulp}.
    function gulp() public override use(aggregationVaultModule) {}

    /// @notice See {VaultModule-deposit}.
    function deposit(uint256 _assets, address _receiver)
        public
        override
        use(aggregationVaultModule)
        returns (uint256)
    {}

    /// @notice See {VaultModule-mint}.
    function mint(uint256 _shares, address _receiver) public override use(aggregationVaultModule) returns (uint256) {}

    /// @notice See {VaultModule-withdraw}.
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        override
        use(aggregationVaultModule)
        returns (uint256 shares)
    {}

    /// @notice See {VaultModule-redeem}.
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        override
        use(aggregationVaultModule)
        returns (uint256 assets)
    {}

    /// @dev Overriding _msgSender().
    function _msgSender() internal view override (Dispatch, ContextUpgradeable) returns (address) {
        return Dispatch._msgSender();
    }
}
