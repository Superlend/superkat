// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBalanceTracker} from "reward-streams/interfaces/IBalanceTracker.sol";
import {IAggregationLayerVault} from "./interface/IAggregationLayerVault.sol";
import {IWithdrawalQueue} from "./interface/IWithdrawalQueue.sol";
// contracts
import {Dispatch} from "./Dispatch.sol";
import {
    ERC4626Upgradeable,
    ERC20Upgradeable
} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Shared} from "./Shared.sol";
import {ContextUpgradeable} from "@openzeppelin-upgradeable/utils/ContextUpgradeable.sol";
// libs
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageLib, AggregationVaultStorage, Strategy} from "./lib/StorageLib.sol";
import {ErrorsLib} from "./lib/ErrorsLib.sol";
import {EventsLib} from "./lib/EventsLib.sol";

/// @dev Do NOT use with fee on transfer tokens
/// @dev Do NOT use with rebasing tokens
/// @dev inspired by Yearn v3 ❤️
contract AggregationLayerVault is
    ERC4626Upgradeable,
    AccessControlEnumerableUpgradeable,
    Dispatch,
    IAggregationLayerVault
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // Roles
    bytes32 public constant ALLOCATIONS_MANAGER = keccak256("ALLOCATIONS_MANAGER");
    bytes32 public constant ALLOCATIONS_MANAGER_ADMIN = keccak256("ALLOCATIONS_MANAGER_ADMIN");
    bytes32 public constant STRATEGY_ADDER = keccak256("STRATEGY_ADDER");
    bytes32 public constant STRATEGY_ADDER_ADMIN = keccak256("STRATEGY_ADDER_ADMIN");
    bytes32 public constant STRATEGY_REMOVER = keccak256("STRATEGY_REMOVER");
    bytes32 public constant STRATEGY_REMOVER_ADMIN = keccak256("STRATEGY_REMOVER_ADMIN");
    bytes32 public constant AGGREGATION_VAULT_MANAGER = keccak256("AGGREGATION_VAULT_MANAGER");
    bytes32 public constant AGGREGATION_VAULT_MANAGER_ADMIN = keccak256("AGGREGATION_VAULT_MANAGER_ADMIN");
    bytes32 public constant REBALANCER = keccak256("REBALANCER");
    bytes32 public constant REBALANCER_ADMIN = keccak256("REBALANCER_ADMIN");

    /// @dev interest rate smearing period
    uint256 public constant INTEREST_SMEAR = 2 weeks;

    /// @dev Euler saving rate struct
    /// @dev Based on https://github.com/euler-xyz/euler-vault-kit/blob/master/src/Synths/EulerSavingsRate.sol
    /// lastInterestUpdate: last timestamo where interest was updated.
    /// interestSmearEnd: timestamp when the smearing of interest end.
    /// interestLeft: amount of interest left to smear.
    /// locked: if locked or not for update.
    struct AggregationVaultSavingRate {
        uint40 lastInterestUpdate;
        uint40 interestSmearEnd;
        uint168 interestLeft;
        uint8 locked;
    }

    struct InitParams {
        address evc;
        address balanceTracker;
        address withdrawalQueuePeriphery;
        address rebalancerPerihpery;
        address aggregationVaultOwner;
        address asset;
        string name;
        string symbol;
        uint256 initialCashAllocationPoints;
    }

    constructor(address _rewardsModule, address _hooksModule, address _feeModule, address _allocationPointsModule)
        Dispatch(_rewardsModule, _hooksModule, _feeModule, _allocationPointsModule)
    {}

    function init(InitParams calldata _initParams) external initializer {
        __ERC4626_init_unchained(IERC20(_initParams.asset));
        __ERC20_init_unchained(_initParams.name, _initParams.symbol);

        if (_initParams.initialCashAllocationPoints == 0) revert ErrorsLib.InitialAllocationPointsZero();

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        $.locked = REENTRANCYLOCK__UNLOCKED;
        $.withdrawalQueue = _initParams.withdrawalQueuePeriphery;
        $.strategies[address(0)] = Strategy({
            allocated: 0,
            allocationPoints: _initParams.initialCashAllocationPoints.toUint120(),
            active: true,
            cap: 0
        });
        $.totalAllocationPoints = _initParams.initialCashAllocationPoints;
        $.evc = _initParams.evc;
        $.balanceTracker = _initParams.balanceTracker;

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _initParams.aggregationVaultOwner);
        // By default, the Rebalancer contract is assigned the REBALANCER role
        _grantRole(REBALANCER, _initParams.rebalancerPerihpery);

        // Setup role admins
        _setRoleAdmin(ALLOCATIONS_MANAGER, ALLOCATIONS_MANAGER_ADMIN);
        _setRoleAdmin(STRATEGY_ADDER, STRATEGY_ADDER_ADMIN);
        _setRoleAdmin(STRATEGY_REMOVER, STRATEGY_REMOVER_ADMIN);
        _setRoleAdmin(AGGREGATION_VAULT_MANAGER, AGGREGATION_VAULT_MANAGER_ADMIN);
        _setRoleAdmin(REBALANCER, REBALANCER_ADMIN);
    }

    /// @dev See {FeeModule-setFeeRecipient}.
    function setFeeRecipient(address _newFeeRecipient) external onlyRole(AGGREGATION_VAULT_MANAGER) use(MODULE_FEE) {}

    /// @dev See {FeeModule-setPerformanceFee}.
    function setPerformanceFee(uint256 _newFee) external onlyRole(AGGREGATION_VAULT_MANAGER) use(MODULE_FEE) {}

    /// @dev See {RewardsModule-optInStrategyRewards}.
    function optInStrategyRewards(address _strategy)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(MODULE_REWARDS)
    {}

    /// @dev See {RewardsModule-optOutStrategyRewards}.
    function optOutStrategyRewards(address _strategy)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(MODULE_REWARDS)
    {}

    /// @dev See {RewardsModule-optOutStrategyRewards}.
    function enableRewardForStrategy(address _strategy, address _reward)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(MODULE_REWARDS)
    {}

    /// @dev See {RewardsModule-disableRewardForStrategy}.
    function disableRewardForStrategy(address _strategy, address _reward, bool _forfeitRecentReward)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(MODULE_REWARDS)
    {}

    /// @dev See {RewardsModule-claimStrategyReward}.
    function claimStrategyReward(address _strategy, address _reward, address _recipient, bool _forfeitRecentReward)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(MODULE_REWARDS)
    {}

    /// @dev See {RewardsModule-enableBalanceForwarder}.
    function enableBalanceForwarder() external override use(MODULE_REWARDS) {}

    /// @dev See {RewardsModule-disableBalanceForwarder}.
    function disableBalanceForwarder() external override use(MODULE_REWARDS) {}

    /// @dev See {AllocationPointsModule-adjustAllocationPoints}.
    function adjustAllocationPoints(address _strategy, uint256 _newPoints)
        external
        use(MODULE_ALLOCATION_POINTS)
        onlyRole(ALLOCATIONS_MANAGER)
    {}

    /// @dev See {AllocationPointsModule-setStrategyCap}.
    function setStrategyCap(address _strategy, uint256 _cap)
        external
        use(MODULE_ALLOCATION_POINTS)
        onlyRole(ALLOCATIONS_MANAGER)
    {}

    /// @dev See {AllocationPointsModule-addStrategy}.
    function addStrategy(address _strategy, uint256 _allocationPoints)
        external
        use(MODULE_ALLOCATION_POINTS)
        onlyRole(STRATEGY_ADDER)
    {}

    /// @dev See {AllocationPointsModule-removeStrategy}.
    function removeStrategy(address _strategy) external use(MODULE_ALLOCATION_POINTS) onlyRole(STRATEGY_REMOVER) {}

    /// @dev See {HooksModule-setHooksConfig}.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns)
        external
        override
        onlyRole(AGGREGATION_VAULT_MANAGER)
        use(MODULE_HOOKS)
    {}

    /// @notice Rebalance strategy by depositing or withdrawing the amount to rebalance to hit target allocation.
    /// @dev Can only be called by an address that hold the REBALANCER role.
    /// @param _strategy Strategy address.
    /// @param _amountToRebalance Amount to deposit or withdraw.
    /// @param _isDeposit bool to indicate if it is a deposit or a withdraw.
    function rebalance(address _strategy, uint256 _amountToRebalance, bool _isDeposit)
        external
        nonReentrant
        onlyRole(REBALANCER)
    {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        Strategy memory strategyData = $.strategies[_strategy];

        if (_isDeposit) {
            // Do required approval (safely) and deposit
            IERC20(asset()).safeIncreaseAllowance(_strategy, _amountToRebalance);
            IERC4626(_strategy).deposit(_amountToRebalance, address(this));
            $.strategies[_strategy].allocated = uint120(strategyData.allocated + _amountToRebalance);
            $.totalAllocated += _amountToRebalance;
        } else {
            IERC4626(_strategy).withdraw(_amountToRebalance, address(this), address(this));
            $.strategies[_strategy].allocated = (strategyData.allocated - _amountToRebalance).toUint120();
            $.totalAllocated -= _amountToRebalance;
        }

        emit EventsLib.Rebalance(_strategy, _amountToRebalance, _isDeposit);
    }

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
    function executeStrategyWithdraw(address _strategy, uint256 _withdrawAmount) external {
        _isCallerWithdrawalQueue();

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        // Update allocated assets
        $.strategies[_strategy].allocated -= uint120(_withdrawAmount);
        $.totalAllocated -= _withdrawAmount;

        // Do actual withdraw from strategy
        IERC4626(_strategy).withdraw(_withdrawAmount, address(this), address(this));
    }

    /// @notice Execute a withdraw from the AggregationVault
    /// @dev This function should be called and can only be called by the WithdrawalQueue.
    /// @param caller Withdraw call initiator.
    /// @param receiver Receiver of the withdrawn asset.
    /// @param owner Owner of shares to withdraw against.
    /// @param assets Amount of asset to withdraw.
    /// @param shares Amount of shares to withdraw against.
    function executeAggregationVaultWithdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) external {
        _isCallerWithdrawalQueue();

        super._withdraw(caller, receiver, owner, assets, shares);

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        $.totalAssetsDeposited -= assets;

        _gulp();
    }

    /// @notice Get strategy params.
    /// @param _strategy strategy's address
    /// @return Strategy struct
    function getStrategy(address _strategy) external view returns (Strategy memory) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

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
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        AggregationVaultSavingRate memory avsr = AggregationVaultSavingRate({
            lastInterestUpdate: $.lastInterestUpdate,
            interestSmearEnd: $.interestSmearEnd,
            interestLeft: $.interestLeft,
            locked: $.locked
        });

        return avsr;
    }

    function totalAllocated() external view returns (uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return $.totalAllocated;
    }

    function totalAllocationPoints() external view returns (uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return $.totalAllocationPoints;
    }

    function totalAssetsDeposited() external view returns (uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return $.totalAssetsDeposited;
    }

    function withdrawalQueue() external view returns (address) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return $.withdrawalQueue;
    }

    function performanceFeeConfig() external view returns (address, uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

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

    /// @notice Return the total amount of assets deposited, plus the accrued interest.
    /// @return uint256 total amount
    function totalAssets() public view override returns (uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return $.totalAssetsDeposited + _interestAccruedFromCache();
    }

    /// @notice get the total assets allocatable
    /// @dev the total assets allocatable is the amount of assets deposited into the aggregator + assets already deposited into strategies
    /// @return uint256 total assets
    function totalAssetsAllocatable() public view returns (uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        return IERC20(asset()).balanceOf(address(this)) + $.totalAllocated;
    }

    /// @dev See {IERC4626-_deposit}.
    /// @dev Increate the total assets deposited.
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override {
        super._deposit(_caller, _receiver, _assets, _shares);

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        $.totalAssetsDeposited += _assets;
    }

    /// @dev See {IERC4626-_withdraw}.
    /// @dev This function do not withdraw assets, it makes call to WithdrawalQueue to finish the withdraw request.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares)
        internal
        override
    {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        uint256 assetsRetrieved = IERC20(asset()).balanceOf(address(this));

        IWithdrawalQueue($.withdrawalQueue).callWithdrawalQueue(
            _caller, _receiver, _owner, _assets, _shares, assetsRetrieved, false
        );
    }

    /// @notice update accrued interest.
    function _updateInterestAccrued() internal {
        uint256 accruedInterest = _interestAccruedFromCache();

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        // it's safe to down-cast because the accrued interest is a fraction of interest left
        $.interestLeft -= uint168(accruedInterest);
        $.lastInterestUpdate = uint40(block.timestamp);

        // Move interest accrued to totalAssetsDeposited
        $.totalAssetsDeposited += accruedInterest;
    }

    /// @dev gulp positive yield into interest left amd update accrued interest.
    function _gulp() internal {
        _updateInterestAccrued();

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if ($.totalAssetsDeposited == 0) return;
        uint256 toGulp = totalAssetsAllocatable() - $.totalAssetsDeposited - $.interestLeft;

        if (toGulp == 0) return;

        uint256 maxGulp = type(uint168).max - $.interestLeft;
        if (toGulp > maxGulp) toGulp = maxGulp; // cap interest, allowing the vault to function

        $.interestSmearEnd = uint40(block.timestamp + INTEREST_SMEAR);
        $.interestLeft += uint168(toGulp); // toGulp <= maxGulp <= max uint168

        emit EventsLib.Gulp($.interestLeft, $.interestSmearEnd);
    }

    /// @dev Loop through stratgies, aggregated yield and lossm and account for net amount.
    /// @dev Loss socialization will be taken out from interest left first, if not enough, sozialize on deposits.
    function _harvest() internal {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

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
            uint256 netLoss = totalLoss - totalYield;

            if ($.interestLeft >= netLoss) {
                // cut loss from interest left only
                $.interestLeft -= uint168(netLoss);
            } else {
                // cut the interest left and socialize the diff
                $.totalAssetsDeposited -= netLoss - $.interestLeft;
                $.interestLeft = 0;
            }
        }

        _gulp();
    }

    /// TODO: better events
    /// @dev Execute harvest on a single strategy.
    /// @param _strategy Strategy address.
    /// @return yiled Amount of yield if any, else 0.
    /// @return loss Amount of loss if any, else 0.
    function _executeHarvest(address _strategy) internal returns (uint256, uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        uint120 strategyAllocatedAmount = $.strategies[_strategy].allocated;

        if (strategyAllocatedAmount == 0) return (0, 0);

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
        emit EventsLib.Harvest(_strategy, underlyingBalance, strategyAllocatedAmount);

        return (yield, loss);
    }

    /// @dev Accrue performace fee on harvested yield.
    /// @param _strategy Strategy that the yield is harvested from.
    /// @param _yield Amount of yield harvested.
    /// @return feeAssets Amount of performance fee taken.
    function _accruePerformanceFee(address _strategy, uint256 _yield) internal returns (uint120) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        address cachedFeeRecipient = $.feeRecipient;
        uint256 cachedPerformanceFee = $.performanceFee;

        if (cachedFeeRecipient == address(0) || cachedPerformanceFee == 0) return 0;

        // `feeAssets` will be rounded down to 0 if `yield * performanceFee < 1e18`.
        uint256 feeAssets = Math.mulDiv(_yield, cachedPerformanceFee, 1e18, Math.Rounding.Floor);

        if (feeAssets > 0) {
            IERC4626(_strategy).withdraw(feeAssets, cachedFeeRecipient, address(this));
        }

        emit EventsLib.AccruePerformanceFee(cachedFeeRecipient, _yield, feeAssets);

        return feeAssets.toUint120();
    }

    /// @dev Override _afterTokenTransfer hook to call IBalanceTracker.balanceTrackerHook()
    /// @dev Calling .balanceTrackerHook() passing the address total balance
    /// @param from Address sending the amount
    /// @param to Address receiving the amount
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (from == to) return;

        IBalanceTracker balanceTracker = IBalanceTracker(_balanceTrackerAddress());

        if ((from != address(0)) && (_balanceForwarderEnabled(from))) {
            balanceTracker.balanceTrackerHook(from, super.balanceOf(from), false);
        }

        if ((to != address(0)) && (_balanceForwarderEnabled(to))) {
            balanceTracker.balanceTrackerHook(to, super.balanceOf(to), false);
        }
    }

    /// @dev Get accrued interest without updating it.
    /// @return uint256 Accrued interest.
    function _interestAccruedFromCache() internal view returns (uint256) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        // If distribution ended, full amount is accrued
        if (block.timestamp >= $.interestSmearEnd) {
            return $.interestLeft;
        }

        // If just updated return 0
        if ($.lastInterestUpdate == block.timestamp) {
            return 0;
        }

        // Else return what has accrued
        uint256 totalDuration = $.interestSmearEnd - $.lastInterestUpdate;
        uint256 timePassed = block.timestamp - $.lastInterestUpdate;

        return $.interestLeft * timePassed / totalDuration;
    }

    /// @dev Override for _msgSender() to be aware of the EVC forwarded calls.
    function _msgSender() internal view override (ContextUpgradeable, Shared) returns (address) {
        return Shared._msgSender();
    }

    /// @dev Check if caller is WithdrawalQueue address, if not revert.
    function _isCallerWithdrawalQueue() internal view {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if (_msgSender() != $.withdrawalQueue) revert ErrorsLib.NotWithdrawaQueue();
    }
}
