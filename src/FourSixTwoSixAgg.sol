// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Shared} from "./Shared.sol";
// external dep
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ERC4626Upgradeable,
    IERC4626,
    ERC20Upgradeable,
    Math
} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// internal dep
import {StorageLib, AggregationVaultStorage, Strategy} from "./lib/StorageLib.sol";
import {ErrorsLib} from "./lib/ErrorsLib.sol";
import {IBalanceTracker} from "reward-streams/interfaces/IBalanceTracker.sol";
import {IFourSixTwoSixAgg} from "./interface/IFourSixTwoSixAgg.sol";
import {IWithdrawalQueue} from "./interface/IWithdrawalQueue.sol";
import {Dispatch} from "./Dispatch.sol";
import {ContextUpgradeable} from "@openzeppelin-upgradeable/utils/ContextUpgradeable.sol";

/// @dev Do NOT use with fee on transfer tokens
/// @dev Do NOT use with rebasing tokens
/// @dev Based on https://github.com/euler-xyz/euler-vault-kit/blob/master/src/Synths/EulerSavingsRate.sol
/// @dev inspired by Yearn v3 ❤️
contract FourSixTwoSixAgg is ERC4626Upgradeable, AccessControlEnumerableUpgradeable, Dispatch, IFourSixTwoSixAgg {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // Roles
    bytes32 public constant STRATEGY_MANAGER = keccak256("STRATEGY_MANAGER");
    bytes32 public constant STRATEGY_MANAGER_ADMIN = keccak256("STRATEGY_MANAGER_ADMIN");
    bytes32 public constant STRATEGY_ADDER = keccak256("STRATEGY_ADDER");
    bytes32 public constant STRATEGY_ADDER_ADMIN = keccak256("STRATEGY_ADDER_ADMIN");
    bytes32 public constant STRATEGY_REMOVER = keccak256("STRATEGY_REMOVER");
    bytes32 public constant STRATEGY_REMOVER_ADMIN = keccak256("STRATEGY_REMOVER_ADMIN");
    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant MANAGER_ADMIN = keccak256("MANAGER_ADMIN");
    bytes32 public constant REBALANCER = keccak256("REBALANCER");
    bytes32 public constant REBALANCER_ADMIN = keccak256("REBALANCER_ADMIN");

    uint256 public constant INTEREST_SMEAR = 2 weeks;

    event Gulp(uint256 interestLeft, uint256 interestSmearEnd);
    event Harvest(address indexed strategy, uint256 strategyBalanceAmount, uint256 strategyAllocatedAmount);
    event AdjustAllocationPoints(address indexed strategy, uint256 oldPoints, uint256 newPoints);
    event AddStrategy(address indexed strategy, uint256 allocationPoints);
    event RemoveStrategy(address indexed _strategy);
    event AccruePerformanceFee(address indexed feeRecipient, uint256 yield, uint256 feeAssets);
    event SetStrategyCap(address indexed strategy, uint256 cap);
    event Rebalance(address indexed strategy, uint256 _amountToRebalance, bool _isDeposit);

    constructor(address _rewardsModule, address _hooksModule, address _feeModule)
        Dispatch(_rewardsModule, _hooksModule, _feeModule)
    {}

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
    // /// @param _evc EVC address
    // /// @param _asset Aggregator's asset address
    // /// @param _name Aggregator's name
    // /// @param _symbol Aggregator's symbol
    // /// @param _initialCashAllocationPoints Initial points to be allocated to the cash reserve
    // /// @param _initialStrategies An array of initial strategies addresses
    // /// @param _initialStrategiesAllocationPoints An array of initial strategies allocation points
    function init(
        address _evc,
        address _balanceTracker,
        address _withdrawalQueue,
        address _rebalancer,
        address _owner,
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external initializer {
        __ERC4626_init_unchained(IERC20(_asset));
        __ERC20_init_unchained(_name, _symbol);

        _lock();

        if (_initialCashAllocationPoints == 0) revert ErrorsLib.InitialAllocationPointsZero();

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();
        $.withdrawalQueue = _withdrawalQueue;
        $.strategies[address(0)] =
            Strategy({allocated: 0, allocationPoints: _initialCashAllocationPoints.toUint120(), active: true, cap: 0});
        $.totalAllocationPoints = _initialCashAllocationPoints;
        $.evc = _evc;

        _setBalanceTracker(_balanceTracker);

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        // By default, the Rebalancer contract is assigned the REBALANCER role
        _grantRole(REBALANCER, _rebalancer);

        // Setup role admins
        _setRoleAdmin(STRATEGY_MANAGER, STRATEGY_MANAGER_ADMIN);
        _setRoleAdmin(STRATEGY_ADDER, STRATEGY_ADDER_ADMIN);
        _setRoleAdmin(STRATEGY_REMOVER, STRATEGY_REMOVER_ADMIN);
        _setRoleAdmin(MANAGER, MANAGER_ADMIN);
        _setRoleAdmin(REBALANCER, REBALANCER_ADMIN);
    }

    /// @notice Set performance fee recipient address
    /// @notice @param _newFeeRecipient Recipient address
    function setFeeRecipient(address _newFeeRecipient) external onlyRole(MANAGER) use(MODULE_FEE) {}

    /// @notice Set performance fee (1e18 == 100%)
    /// @notice @param _newFee Fee rate
    function setPerformanceFee(uint256 _newFee) external onlyRole(MANAGER) use(MODULE_FEE) {}

    /// @notice Opt in to strategy rewards
    /// @param _strategy Strategy address
    function optInStrategyRewards(address _strategy) external override onlyRole(MANAGER) use(MODULE_REWARDS) {}

    /// @notice Opt out of strategy rewards
    /// @param _strategy Strategy address
    function optOutStrategyRewards(address _strategy) external override onlyRole(MANAGER) use(MODULE_REWARDS) {}

    /// @notice Claim a specific strategy rewards
    /// @param _strategy Strategy address.
    /// @param _reward The address of the reward token.
    /// @param _recipient The address to receive the claimed reward tokens.
    /// @param _forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    function claimStrategyReward(address _strategy, address _reward, address _recipient, bool _forfeitRecentReward)
        external
        override
        onlyRole(MANAGER)
        use(MODULE_REWARDS)
    {}

    /// @notice Enables balance forwarding for sender
    /// @dev Should call the IBalanceTracker hook with the current user's balance
    function enableBalanceForwarder() external override use(MODULE_REWARDS) {}

    /// @notice Disables balance forwarding for the sender
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function disableBalanceForwarder() external override use(MODULE_REWARDS) {}

    /// @notice Harvest strategy.
    /// @param strategy address of strategy
    //TODO: is this safe without the reentrancy check
    function harvest(address strategy) external {
        _harvest(strategy);

        _gulp();
    }

    /// @notice Harvest multiple strategies.
    /// @param _strategies an array of strategy addresses.
    function harvestMultipleStrategies(address[] calldata _strategies) external nonReentrant {
        for (uint256 i; i < _strategies.length; ++i) {
            _harvest(_strategies[i]);
        }
        _gulp();
    }

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

        emit Rebalance(_strategy, _amountToRebalance, _isDeposit);
    }

    /// @notice Adjust a certain strategy's allocation points.
    /// @dev Can only be called by an address that have the STRATEGY_MANAGER
    /// @param _strategy address of strategy
    /// @param _newPoints new strategy's points
    function adjustAllocationPoints(address _strategy, uint256 _newPoints)
        external
        nonReentrant
        onlyRole(STRATEGY_MANAGER)
    {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        Strategy memory strategyDataCache = $.strategies[_strategy];

        if (!strategyDataCache.active) {
            revert ErrorsLib.InactiveStrategy();
        }

        $.strategies[_strategy].allocationPoints = _newPoints.toUint120();
        $.totalAllocationPoints = $.totalAllocationPoints + _newPoints - strategyDataCache.allocationPoints;

        emit AdjustAllocationPoints(_strategy, strategyDataCache.allocationPoints, _newPoints);
    }

    /// @notice Set cap on strategy allocated amount.
    /// @dev By default, cap is set to 0, not activated.
    /// @param _strategy Strategy address.
    /// @param _cap Cap amount
    function setStrategyCap(address _strategy, uint256 _cap) external nonReentrant onlyRole(STRATEGY_MANAGER) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if (!$.strategies[_strategy].active) {
            revert ErrorsLib.InactiveStrategy();
        }

        $.strategies[_strategy].cap = _cap.toUint120();

        emit SetStrategyCap(_strategy, _cap);
    }

    /// @notice Add new strategy with it's allocation points.
    /// @dev Can only be called by an address that have STRATEGY_ADDER.
    /// @param _strategy Address of the strategy
    /// @param _allocationPoints Strategy's allocation points
    function addStrategy(address _strategy, uint256 _allocationPoints) external nonReentrant onlyRole(STRATEGY_ADDER) {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if ($.strategies[_strategy].active) {
            revert ErrorsLib.StrategyAlreadyExist();
        }

        if (IERC4626(_strategy).asset() != asset()) {
            revert ErrorsLib.InvalidStrategyAsset();
        }

        _callHooksTarget(ADD_STRATEGY, _msgSender());

        $.strategies[_strategy] =
            Strategy({allocated: 0, allocationPoints: _allocationPoints.toUint120(), active: true, cap: 0});

        $.totalAllocationPoints += _allocationPoints;
        IWithdrawalQueue($.withdrawalQueue).addStrategyToWithdrawalQueue(_strategy);

        emit AddStrategy(_strategy, _allocationPoints);
    }

    /// @notice Remove strategy and set its allocation points to zero.
    /// @dev This function does not pull funds, `harvest()` needs to be called to withdraw
    /// @dev Can only be called by an address that have the STRATEGY_REMOVER
    /// @param _strategy Address of the strategy
    function removeStrategy(address _strategy) external nonReentrant onlyRole(STRATEGY_REMOVER) {
        if (_strategy == address(0)) revert ErrorsLib.CanNotRemoveCashReserve();

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        Strategy storage strategyStorage = $.strategies[_strategy];

        if (!strategyStorage.active) {
            revert ErrorsLib.AlreadyRemoved();
        }

        _callHooksTarget(REMOVE_STRATEGY, _msgSender());

        $.totalAllocationPoints -= strategyStorage.allocationPoints;
        strategyStorage.active = false;
        strategyStorage.allocationPoints = 0;

        // remove from withdrawalQueue
        IWithdrawalQueue($.withdrawalQueue).removeStrategyFromWithdrawalQueue(_strategy);

        emit RemoveStrategy(_strategy);
    }

    /// @notice update accrued interest
    function updateInterestAccrued() external {
        return _updateInterestAccrued();
    }

    /// @notice gulp positive harvest yield
    function gulp() external nonReentrant {
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
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @dev See {IERC4626-mint}.
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @dev See {IERC4626-withdraw}.
    /// @dev this function update the accrued interest
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        // Move interest to totalAssetsDeposited
        _updateInterestAccrued();
        return super.withdraw(assets, receiver, owner);
    }

    /// @dev See {IERC4626-redeem}.
    /// @dev this function update the accrued interest
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        // Move interest to totalAssetsDeposited
        _updateInterestAccrued();
        return super.redeem(shares, receiver, owner);
    }

    /// @notice Set hooks contract and hooked functions.
    /// @dev This funtion should be overriden to implement access control.
    /// @param _hooksTarget Hooks contract.
    /// @param _hookedFns Hooked functions.
    function setHooksConfig(address _hooksTarget, uint32 _hookedFns)
        external
        override
        onlyRole(MANAGER)
        use(MODULE_HOOKS)
    {}

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

    /// @dev Increate the total assets deposited, and call IERC4626._deposit()
    /// @dev See {IERC4626-_deposit}.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _callHooksTarget(DEPOSIT, caller);

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        $.totalAssetsDeposited += assets;

        super._deposit(caller, receiver, assets, shares);
    }

    /// @dev Withdraw asset back to the user.
    /// @dev See {IERC4626-_withdraw}.
    /// @dev if the cash reserve can not cover the amount to withdraw, this function will loop through the strategies
    ///      to cover the remaining amount. This function will revert if the amount to withdraw is not available
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _callHooksTarget(WITHDRAW, caller);

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        $.totalAssetsDeposited -= assets;
        uint256 assetsRetrieved = IERC20(asset()).balanceOf(address(this));

        if (assetsRetrieved < assets) {
            IWithdrawalQueue($.withdrawalQueue).executeWithdrawFromQueue(
                caller, receiver, owner, assets, shares, assetsRetrieved
            );
        } else {
            _executeWithdrawFromReserve(caller, receiver, owner, assets, shares);
        }
    }

    // TODO: add access control
    function withdrawFromStrategy(address _strategy, uint256 _withdrawAmount) external {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        // Update allocated assets
        $.strategies[_strategy].allocated -= uint120(_withdrawAmount);
        $.totalAllocated -= _withdrawAmount;

        // Do actual withdraw from strategy
        IERC4626(_strategy).withdraw(_withdrawAmount, address(this), address(this));
    }

    // TODO: add access control
    function executeWithdrawFromReserve(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        external
    {
        _executeWithdrawFromReserve(caller, receiver, owner, assets, shares);
    }

    // TODO: add access control
    function _executeWithdrawFromReserve(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal {
        _gulp();

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev gulp positive yield and increment the left interest
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

        emit Gulp($.interestLeft, $.interestSmearEnd);
    }

    function _harvest(address _strategy) internal {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        uint120 strategyAllocatedAmount = $.strategies[_strategy].allocated;

        if (strategyAllocatedAmount == 0) return;

        uint256 underlyingBalance = IERC4626(_strategy).maxWithdraw(address(this));

        if (underlyingBalance == strategyAllocatedAmount) {
            return;
        } else if (underlyingBalance > strategyAllocatedAmount) {
            // There's yield!
            uint256 yield = underlyingBalance - strategyAllocatedAmount;
            uint120 accruedPerformanceFee = _accruePerformanceFee(_strategy, yield);

            if (accruedPerformanceFee > 0) {
                underlyingBalance -= accruedPerformanceFee;
                yield -= accruedPerformanceFee;
            }

            $.strategies[_strategy].allocated = uint120(underlyingBalance);
            $.totalAllocated += yield;
        } else {
            uint256 loss = strategyAllocatedAmount - underlyingBalance;

            $.strategies[_strategy].allocated = uint120(underlyingBalance);
            $.totalAllocated -= loss;

            if ($.interestLeft >= loss) {
                $.interestLeft -= uint168(loss);
            } else {
                $.totalAssetsDeposited -= loss - $.interestLeft;
                $.interestLeft = 0;
            }
        }

        emit Harvest(_strategy, underlyingBalance, strategyAllocatedAmount);
    }

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

        emit AccruePerformanceFee(cachedFeeRecipient, _yield, feeAssets);

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
    /// @return uint256 accrued interest
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

    function _lock() private onlyInitializing {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        $.locked = REENTRANCYLOCK__UNLOCKED;
    }

    function _msgSender() internal view override (ContextUpgradeable, Shared) returns (address) {
        return Shared._msgSender();
    }
}
