// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBalanceTracker} from "reward-streams/interfaces/IBalanceTracker.sol";
import {IEulerAggregationVault} from "./interface/IEulerAggregationVault.sol";
import {IWithdrawalQueue} from "./interface/IWithdrawalQueue.sol";
// contracts
import {Dispatch} from "./Dispatch.sol";
import {
    ERC20Upgradeable,
    ERC4626Upgradeable
} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Shared} from "./common/Shared.sol";
// libs
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageLib as Storage, AggregationVaultStorage} from "./lib/StorageLib.sol";
import {ErrorsLib as Errors} from "./lib/ErrorsLib.sol";
import {EventsLib as Events} from "./lib/EventsLib.sol";

/// @title EulerAggregationVault contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @dev Do NOT use with fee on transfer tokens
/// @dev Do NOT use with rebasing tokens
/// @dev inspired by Yearn v3 ❤️
contract EulerAggregationVault is
    ERC4626Upgradeable,
    ERC20VotesUpgradeable,
    AccessControlEnumerableUpgradeable,
    Dispatch,
    IEulerAggregationVault
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // Roles
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");
    bytes32 public constant GUARDIAN_ADMIN = keccak256("GUARDIAN_ADMIN");
    bytes32 public constant STRATEGY_OPERATOR = keccak256("STRATEGY_OPERATOR");
    bytes32 public constant STRATEGY_OPERATOR_ADMIN = keccak256("STRATEGY_OPERATOR_ADMIN");
    bytes32 public constant AGGREGATION_VAULT_MANAGER = keccak256("AGGREGATION_VAULT_MANAGER");
    bytes32 public constant AGGREGATION_VAULT_MANAGER_ADMIN = keccak256("AGGREGATION_VAULT_MANAGER_ADMIN");

    /// @dev Constructor.
    constructor(ConstructorParams memory _constructorParams)
        Dispatch(
            _constructorParams.rewardsModule,
            _constructorParams.hooksModule,
            _constructorParams.feeModule,
            _constructorParams.strategyModule,
            _constructorParams.rebalanceModule
        )
    {}

    /// @notice Initialize the EulerAggregationVault.
    /// @param _initParams InitParams struct.
    function init(InitParams calldata _initParams) external initializer {
        __ERC4626_init_unchained(IERC20(_initParams.asset));
        __ERC20_init_unchained(_initParams.name, _initParams.symbol);
        __AccessControlEnumerable_init();

        if (_initParams.initialCashAllocationPoints == 0) revert Errors.InitialAllocationPointsZero();

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.locked = REENTRANCYLOCK__UNLOCKED;
        $.withdrawalQueue = _initParams.withdrawalQueuePlugin;
        $.balanceTracker = _initParams.balanceTracker;
        $.strategies[address(0)] = IEulerAggregationVault.Strategy({
            allocated: 0,
            allocationPoints: _initParams.initialCashAllocationPoints.toUint120(),
            status: IEulerAggregationVault.StrategyStatus.Active,
            cap: 0
        });
        $.totalAllocationPoints = _initParams.initialCashAllocationPoints;

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _initParams.aggregationVaultOwner);

        // Setup role admins
        _setRoleAdmin(GUARDIAN, GUARDIAN_ADMIN);
        _setRoleAdmin(STRATEGY_OPERATOR, STRATEGY_OPERATOR_ADMIN);
        _setRoleAdmin(AGGREGATION_VAULT_MANAGER, AGGREGATION_VAULT_MANAGER_ADMIN);

        IWithdrawalQueue(_initParams.withdrawalQueuePlugin).init(_initParams.aggregationVaultOwner);
    }

    /// @dev See {FeeModule-setFeeRecipient}.
    function setFeeRecipient(address _newFeeRecipient)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(feeModule)
    {}

    /// @dev See {FeeModule-setPerformanceFee}.
    function setPerformanceFee(uint256 _newFee) external override onlyRole(AGGREGATION_VAULT_MANAGER) use(feeModule) {}

    /// @dev See {RewardsModule-optInStrategyRewards}.
    function optInStrategyRewards(address _strategy)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-optOutStrategyRewards}.
    function optOutStrategyRewards(address _strategy)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-optOutStrategyRewards}.
    function enableRewardForStrategy(address _strategy, address _reward)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-disableRewardForStrategy}.
    function disableRewardForStrategy(address _strategy, address _reward, bool _forfeitRecentReward)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(rewardsModule)
    {}

    /// @dev See {RewardsModule-claimStrategyReward}.
    function claimStrategyReward(address _strategy, address _reward, address _recipient, bool _forfeitRecentReward)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(rewardsModule)
    {}

    /// @dev See {HooksModule-setHooksConfig}.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(hooksModule)
    {}

    /// @dev See {StrategyModule-addStrategy}.
    function addStrategy(address _strategy, uint256 _allocationPoints)
        external
        override
        onlyRole(STRATEGY_OPERATOR)
        use(strategyModule)
    {}

    /// @dev See {StrategyModule-removeStrategy}.
    function removeStrategy(address _strategy) external override onlyRole(STRATEGY_OPERATOR) use(strategyModule) {}

    /// @dev See {StrategyModule-setStrategyCap}.
    function setStrategyCap(address _strategy, uint256 _cap) external override onlyRole(GUARDIAN) use(strategyModule) {}

    /// @dev See {StrategyModule-adjustAllocationPoints}.
    function adjustAllocationPoints(address _strategy, uint256 _newPoints)
        external
        override
        onlyRole(GUARDIAN)
        use(strategyModule)
    {}

    /// @dev See {StrategyModule-toggleStrategyEmergencyStatus}.
    function toggleStrategyEmergencyStatus(address _strategy)
        external
        override
        onlyRole(GUARDIAN)
        use(strategyModule)
    {}

    /// @dev See {RewardsModule-enableBalanceForwarder}.
    function enableBalanceForwarder() external override use(rewardsModule) {}

    /// @dev See {RewardsModule-disableBalanceForwarder}.
    function disableBalanceForwarder() external override use(rewardsModule) {}

    function executeRebalance(address[] calldata _strategies) external override use(rebalanceModule) {}

    /// @notice Harvest all the strategies.
    /// @dev This function will loop through the strategies following the withdrawal queue order and harvest all.
    /// @dev Harvest yield and losses will be aggregated and only net yield/loss will be accounted.
    function harvest() external nonReentrant {
        _updateInterestAccrued();

        _harvest();
    }

    /// @notice update accrued interest
    function updateInterestAccrued() external {
        return _updateInterestAccrued();
    }

    /// @notice gulp positive harvest yield
    function gulp() external nonReentrant {
        _gulp();
    }

    /// @notice Execute a withdraw from a strategy.
    /// @dev Can only be called from the WithdrawalQueue contract.
    /// @param _strategy Strategy's address.
    /// @param _withdrawAmount Amount to withdraw.
    function executeStrategyWithdraw(address _strategy, uint256 _withdrawAmount) external returns (uint256) {
        _isCallerWithdrawalQueue();

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        if ($.strategies[_strategy].status != IEulerAggregationVault.StrategyStatus.Active) return 0;

        // Update allocated assets
        $.strategies[_strategy].allocated -= uint120(_withdrawAmount);
        $.totalAllocated -= _withdrawAmount;

        // Do actual withdraw from strategy
        IERC4626(_strategy).withdraw(_withdrawAmount, address(this), address(this));

        return _withdrawAmount;
    }

    /// @notice Execute a withdraw from the AggregationVault
    /// @dev This function should be called and can only be called by the WithdrawalQueue.
    /// @param _caller Withdraw call initiator.
    /// @param _receiver Receiver of the withdrawn asset.
    /// @param _owner Owner of shares to withdraw against.
    /// @param _assets Amount of asset to withdraw.
    /// @param _shares Amount of shares to withdraw against.
    function executeAggregationVaultWithdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    ) external {
        _isCallerWithdrawalQueue();

        super._withdraw(_caller, _receiver, _owner, _assets, _shares);

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.totalAssetsDeposited -= _assets;

        _gulp();
    }

    /// @notice Get strategy params.
    /// @param _strategy strategy's address
    /// @return Strategy struct
    function getStrategy(address _strategy) external view returns (IEulerAggregationVault.Strategy memory) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.strategies[_strategy];
    }

    /// @notice Return the accrued interest
    /// @return uint256 accrued interest
    function interestAccrued() external view returns (uint256) {
        return _interestAccruedFromCache();
    }

    /// @notice Get saving rate data.
    /// @return avsr AggregationVaultSavingRate struct.
    function getAggregationVaultSavingRate() external view returns (AggregationVaultSavingRate memory) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        AggregationVaultSavingRate memory avsr = AggregationVaultSavingRate({
            lastInterestUpdate: $.lastInterestUpdate,
            interestSmearEnd: $.interestSmearEnd,
            interestLeft: $.interestLeft,
            locked: $.locked
        });

        return avsr;
    }

    /// @notice Get the total allocated amount.
    /// @return uint256 Total allocated.
    function totalAllocated() external view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAllocated;
    }

    /// @notice Get the total allocation points.
    /// @return uint256 Total allocation points.
    function totalAllocationPoints() external view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAllocationPoints;
    }

    /// @notice Get the total assets deposited into the aggregation vault.
    /// @return uint256 Total assets deposited.
    function totalAssetsDeposited() external view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAssetsDeposited;
    }

    /// @notice Get the WithdrawalQueue plugin address.
    /// @return address Withdrawal queue address.
    function withdrawalQueue() external view returns (address) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.withdrawalQueue;
    }

    /// @notice Get the performance fee config.
    /// @return adddress Fee recipient.
    /// @return uint256 Fee percentage.
    function performanceFeeConfig() external view returns (address, uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return ($.feeRecipient, $.performanceFee);
    }

    /// @dev See {IERC4626-deposit}.
    /// @dev Call DEPOSIT hook if enabled.
    function deposit(uint256 _assets, address _receiver) public override nonReentrant returns (uint256) {
        _callHooksTarget(DEPOSIT, _msgSender());

        return super.deposit(_assets, _receiver);
    }

    /// @dev See {IERC4626-mint}.
    /// @dev Call MINT hook if enabled.
    function mint(uint256 _shares, address _receiver) public override nonReentrant returns (uint256) {
        _callHooksTarget(MINT, _msgSender());

        return super.mint(_shares, _receiver);
    }

    /// @dev See {IERC4626-withdraw}.
    /// @dev this function update the accrued interest and call WITHDRAW hook.
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        // Move interest to totalAssetsDeposited
        _updateInterestAccrued();

        _callHooksTarget(WITHDRAW, _msgSender());

        _harvest();

        return super.withdraw(_assets, _receiver, _owner);
    }

    /// @dev See {IERC4626-redeem}.
    /// @dev this function update the accrued interest and call WITHDRAW hook.
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        // Move interest to totalAssetsDeposited
        _updateInterestAccrued();

        _callHooksTarget(REDEEM, _msgSender());

        _harvest();

        return super.redeem(_shares, _receiver, _owner);
    }

    /// @dev See {IERC20Metadata-decimals}.
    function decimals() public view virtual override (ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /// @notice Return the total amount of assets deposited, plus the accrued interest.
    /// @return uint256 total amount
    function totalAssets() public view override returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAssetsDeposited + _interestAccruedFromCache();
    }

    /// @notice get the total assets allocatable
    /// @dev the total assets allocatable is the amount of assets deposited into the aggregator + assets already deposited into strategies
    /// @return uint256 total assets
    function totalAssetsAllocatable() public view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return IERC20(asset()).balanceOf(address(this)) + $.totalAllocated;
    }

    /// @dev See {IERC4626-_deposit}.
    /// @dev Increate the total assets deposited.
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override {
        super._deposit(_caller, _receiver, _assets, _shares);

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.totalAssetsDeposited += _assets;
    }

    /// @dev See {IERC4626-_withdraw}.
    /// @dev This function do not withdraw assets, it makes call to WithdrawalQueue to finish the withdraw request.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares)
        internal
        override
    {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        uint256 assetsRetrieved = IERC20(asset()).balanceOf(address(this));

        IWithdrawalQueue($.withdrawalQueue).callWithdrawalQueue(
            _caller, _receiver, _owner, _assets, _shares, assetsRetrieved
        );
    }

    /// @dev Loop through stratgies, aggregate positive yield and loss and account for net amount.
    /// @dev Loss socialization will be taken out from interest left first, if not enough, sozialize on deposits.
    function _harvest() internal {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        (address[] memory withdrawalQueueArray, uint256 length) =
            IWithdrawalQueue($.withdrawalQueue).getWithdrawalQueueArray();

        uint256 totalYield;
        uint256 totalLoss;
        for (uint256 i; i < length; ++i) {
            (uint256 yield, uint256 loss) = _executeHarvest(withdrawalQueueArray[i]);

            totalYield += yield;
            totalLoss += loss;
        }

        $.totalAllocated = $.totalAllocated + totalYield - totalLoss;

        if (totalLoss > totalYield) {
            _deductLoss(totalLoss - totalYield);
        }

        emit Events.Harvest($.totalAllocated, totalYield, totalLoss);

        _gulp();
    }

    /// @dev Execute harvest on a single strategy.
    /// @param _strategy Strategy address.
    /// @return yield Amount of yield if any, else 0.
    /// @return loss Amount of loss if any, else 0.
    function _executeHarvest(address _strategy) internal returns (uint256, uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        uint120 strategyAllocatedAmount = $.strategies[_strategy].allocated;

        if (
            strategyAllocatedAmount == 0
                || $.strategies[_strategy].status != IEulerAggregationVault.StrategyStatus.Active
        ) return (0, 0);

        uint256 underlyingBalance = IERC4626(_strategy).maxWithdraw(address(this));
        uint256 yield;
        uint256 loss;
        if (underlyingBalance == strategyAllocatedAmount) {
            return (yield, loss);
        } else if (underlyingBalance > strategyAllocatedAmount) {
            yield = underlyingBalance - strategyAllocatedAmount;
            uint120 accruedPerformanceFee = _accruePerformanceFee(_strategy, yield);

            if (accruedPerformanceFee > 0) {
                underlyingBalance -= accruedPerformanceFee;
                yield -= accruedPerformanceFee;
            }

            $.strategies[_strategy].allocated = uint120(underlyingBalance);
        } else {
            loss = strategyAllocatedAmount - underlyingBalance;

            $.strategies[_strategy].allocated = uint120(underlyingBalance);
        }
        emit Events.ExecuteHarvest(_strategy, underlyingBalance, strategyAllocatedAmount);

        return (yield, loss);
    }

    /// @dev Accrue performace fee on harvested yield.
    /// @param _strategy Strategy that the yield is harvested from.
    /// @param _yield Amount of yield harvested.
    /// @return feeAssets Amount of performance fee taken.
    function _accruePerformanceFee(address _strategy, uint256 _yield) internal returns (uint120) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        address cachedFeeRecipient = $.feeRecipient;
        uint256 cachedPerformanceFee = $.performanceFee;

        if (cachedFeeRecipient == address(0) || cachedPerformanceFee == 0) return 0;

        // `feeAssets` will be rounded down to 0 if `yield * performanceFee < 1e18`.
        uint256 feeAssets = Math.mulDiv(_yield, cachedPerformanceFee, 1e18, Math.Rounding.Floor);

        if (feeAssets > 0) {
            IERC4626(_strategy).withdraw(feeAssets, cachedFeeRecipient, address(this));
        }

        emit Events.AccruePerformanceFee(cachedFeeRecipient, _yield, feeAssets);

        return feeAssets.toUint120();
    }

    /// @dev Override _afterTokenTransfer hook to call IBalanceTracker.balanceTrackerHook()
    /// @dev Calling .balanceTrackerHook() passing the address total balance
    /// @param from Address sending the amount
    /// @param to Address receiving the amount
    function _update(address from, address to, uint256 value)
        internal
        override (ERC20VotesUpgradeable, ERC20Upgradeable)
    {
        ERC20VotesUpgradeable._update(from, to, value);

        if (from == to) return;

        IBalanceTracker balanceTracker = IBalanceTracker(_balanceTrackerAddress());

        if ((from != address(0)) && (_balanceForwarderEnabled(from))) {
            balanceTracker.balanceTrackerHook(from, super.balanceOf(from), false);
        }

        if ((to != address(0)) && (_balanceForwarderEnabled(to))) {
            balanceTracker.balanceTrackerHook(to, super.balanceOf(to), false);
        }
    }

    /// @dev Check if caller is WithdrawalQueue address, if not revert.
    function _isCallerWithdrawalQueue() internal view {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        if (_msgSender() != $.withdrawalQueue) revert Errors.NotWithdrawaQueue();
    }
}
