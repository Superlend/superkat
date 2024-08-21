// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";
import {IBalanceTracker} from "reward-streams/src/interfaces/IBalanceTracker.sol";
// contracts
import {Shared} from "../common/Shared.sol";
import {
    ERC20Upgradeable,
    ERC4626Upgradeable
} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin-upgradeable/utils/ContextUpgradeable.sol";
// libs
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageLib as Storage, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {AmountCapLib, AmountCap} from "../lib/AmountCapLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";

/// @title AggregationVaultModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract AggregationVaultModule is ERC4626Upgradeable, ERC20VotesUpgradeable, Shared {
    using Math for uint256;

    /// @dev Cool down period for harvest call during withdraw operation.
    uint256 public constant HARVEST_COOLDOWN = 1 days;

    /// @notice Harvest all the strategies.
    /// @dev This function will loop through the strategies following the withdrawal queue order and harvest all.
    ///      Harvested positive and negative yields will be aggregated and only net amount will be accounted.
    /// @dev This function does not check for the cooldown period.
    function harvest() public virtual nonReentrant {
        _updateInterestAccrued();

        _harvest(false);
    }

    /// @notice Update accrued interest and count it in the total assets deposited.
    function updateInterestAccrued() public virtual nonReentrant {
        _updateInterestAccrued();
    }

    /// @notice Gulp positive yield.
    function gulp() public virtual nonReentrant {
        _gulp();
    }

    /// @notice Deposit `_assets` amount into the yield aggregator.
    /// @dev See {IERC4626-deposit}.
    /// @dev This function will call DEPOSIT hook if enabled.
    /// @return Amount of shares minted.
    function deposit(uint256 _assets, address _receiver) public virtual override nonReentrant returns (uint256) {
        _callHooksTarget(DEPOSIT, _msgSender());

        uint256 maxAssets = _maxDeposit();
        if (_assets > maxAssets) {
            revert Errors.ERC4626ExceededMaxDeposit(_receiver, _assets, maxAssets);
        }

        uint256 shares = _convertToShares(_assets, Math.Rounding.Floor);
        _deposit(_msgSender(), _receiver, _assets, shares);

        return shares;
    }

    /// @notice Mint `_shares` amount.
    /// @dev See {IERC4626-mint}.
    /// @dev This function will call MINT hook if enabled.
    /// @return Amount of assets deposited.
    function mint(uint256 _shares, address _receiver) public virtual override nonReentrant returns (uint256) {
        _callHooksTarget(MINT, _msgSender());

        uint256 maxShares = _maxMint();
        if (_shares > maxShares) {
            revert Errors.ERC4626ExceededMaxMint(_receiver, _shares, maxShares);
        }

        uint256 assets = _convertToAssets(_shares, Math.Rounding.Ceil);
        _deposit(_msgSender(), _receiver, assets, _shares);

        return assets;
    }

    /// @notice Withdraw `_assets` amount from yield aggregator. This function will try to withdraw from cash reserve,
    ///         if not enough, will loop through the strategies following the withdrawal queue order till the withdraw amount is filled.
    /// @dev See {IERC4626-withdraw}.
    /// @dev This function will update the accrued interest and call WITHDRAW hook if enabled.
    /// @return Amount of shares burned.
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        _updateInterestAccrued();

        _callHooksTarget(WITHDRAW, _msgSender());

        _harvest(true);

        uint256 maxAssets = _convertToAssets(_balanceOf(_owner), Math.Rounding.Floor);
        if (_assets > maxAssets) {
            revert Errors.ERC4626ExceededMaxWithdraw(_owner, _assets, maxAssets);
        }

        uint256 shares = _convertToShares(_assets, Math.Rounding.Ceil);
        _withdraw(_msgSender(), _receiver, _owner, _assets, shares);

        return shares;
    }

    /// @notice Redeem `_shares` amount from yield aggregator. This function will try to withdraw from cash reserve,
    ///         if not enough, will loop through the strategies following the withdrawal queue order till the withdraw amount is filled.
    /// @dev See {IERC4626-redeem}.
    /// @dev This function will update the accrued interest and call REDEEM hook if enabled.
    /// @return Amount of assets withdrawn.
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        _updateInterestAccrued();

        _callHooksTarget(REDEEM, _msgSender());

        _harvest(true);

        uint256 maxShares = _balanceOf(_owner);
        if (_shares > maxShares) {
            revert Errors.ERC4626ExceededMaxRedeem(_owner, _shares, maxShares);
        }

        uint256 assets = _convertToAssets(_shares, Math.Rounding.Floor);
        _withdraw(_msgSender(), _receiver, _owner, assets, _shares);

        return assets;
    }

    /// @notice Return the accrued interest.
    /// @return Accrued interest.
    function interestAccrued() public view virtual nonReentrantView returns (uint256) {
        return _interestAccruedFromCache();
    }

    /// @notice Get saving rate data.
    /// @return Last interest update timestamp.
    /// @return Timestamp when interest smearing end.
    /// @return Amount of interest left to distribute.
    function getAggregationVaultSavingRate() public view virtual nonReentrantView returns (uint40, uint40, uint168) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return ($.lastInterestUpdate, $.interestSmearEnd, $.interestLeft);
    }

    /// @notice Get the total allocated amount.
    /// @return Total allocated amount.
    function totalAllocated() public view virtual nonReentrantView returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAllocated;
    }

    /// @notice Get the total assets deposited into the aggregation vault.
    /// @return Total assets deposited.
    function totalAssetsDeposited() public view virtual nonReentrantView returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAssetsDeposited;
    }

    /// @notice Get the latest harvest timestamp.
    /// @return Latest harvest timestamp.
    function lastHarvestTimestamp() public view virtual nonReentrantView returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.lastHarvestTimestamp;
    }

    /// @notice get the total assets allocatable
    /// @dev the total assets allocatable is the amount of assets deposited into the aggregator + assets already deposited into strategies
    /// @return total assets allocatable.
    function totalAssetsAllocatable() public view virtual nonReentrantView returns (uint256) {
        return _totalAssetsAllocatable();
    }

    /// @notice Return the total amount of assets deposited, plus the accrued interest.
    /// @return total assets amount.
    function totalAssets() public view virtual override nonReentrantView returns (uint256) {
        return _totalAssets();
    }

    /// @notice Convert to the amount of shares that the Vault would exchange for the amount of assets provided.
    /// @dev See {IERC4626-convertToShares}.
    /// @return Amount of shares.
    function convertToShares(uint256 _assets) public view virtual override nonReentrantView returns (uint256) {
        return _convertToShares(_assets, Math.Rounding.Floor);
    }

    /// @notice Convert to the amount of assets that the Vault would exchange for the amount of shares provided.
    /// @dev See {IERC4626-convertToAssets}.
    /// @return Amount of assets.
    function convertToAssets(uint256 _shares) public view virtual override nonReentrantView returns (uint256) {
        return _convertToAssets(_shares, Math.Rounding.Floor);
    }

    /// @notice Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance.
    /// @dev See {IERC4626-maxWithdraw}.
    /// @return Amount of asset to be withdrawn.
    function maxWithdraw(address _owner) public view virtual override nonReentrantView returns (uint256) {
        return _convertToAssets(_balanceOf(_owner), Math.Rounding.Floor);
    }

    /// @notice Returns the maximum amount of Vault shares that can be redeemed from the owner balance in the Vault
    /// @dev See {IERC4626-maxRedeem}.
    /// @return Amount of shares.
    function maxRedeem(address _owner) public view virtual override nonReentrantView returns (uint256) {
        return _balanceOf(_owner);
    }

    /// @notice Preview a deposit call and return the amount of shares to be minted.
    /// @dev See {IERC4626-previewDeposit}.
    /// @return Amount of shares.
    function previewDeposit(uint256 _assets) public view virtual override nonReentrantView returns (uint256) {
        return _convertToShares(_assets, Math.Rounding.Floor);
    }

    /// @notice Preview a mint call and return the amount of assets to be deposited.
    /// @dev See {IERC4626-previewMint}.
    /// @return Amount of assets.
    function previewMint(uint256 _shares) public view virtual override nonReentrantView returns (uint256) {
        return _convertToAssets(_shares, Math.Rounding.Ceil);
    }

    /// @notice Preview a withdraw call and return the amount of shares to be burned.
    /// @dev See {IERC4626-previewWithdraw}.
    /// @return Amount of shares.
    function previewWithdraw(uint256 _assets) public view virtual override nonReentrantView returns (uint256) {
        return _convertToShares(_assets, Math.Rounding.Ceil);
    }

    /// @notice Preview a redeem call and return the amount of assets to be withdrawn.
    /// @dev See {IERC4626-previewRedeem}.
    /// @return Amount of assets.
    function previewRedeem(uint256 _shares) public view virtual override nonReentrantView returns (uint256) {
        return _convertToAssets(_shares, Math.Rounding.Floor);
    }

    /// @notice Return the `_account` aggregator's balance.
    /// @dev Overriding this function to add the `nonReentrantView` modifier.
    function balanceOf(address _account)
        public
        view
        virtual
        override (ERC20Upgradeable, IERC20)
        nonReentrantView
        returns (uint256)
    {
        return _balanceOf(_account);
    }

    /// @notice Return the yield aggregator total balance.
    /// @dev Overriding this function to add the `nonReentrantView` modifier.
    function totalSupply() public view virtual override (ERC20Upgradeable, IERC20) nonReentrantView returns (uint256) {
        return _totalSupply();
    }

    /// @notice Return the yield aggregator token decimals.
    function decimals()
        public
        view
        virtual
        override (ERC4626Upgradeable, ERC20Upgradeable)
        nonReentrantView
        returns (uint8)
    {
        return ERC4626Upgradeable.decimals();
    }

    /// @notice Returns the maximum amount of the underlying asset that can be deposited into the yield aggregator.
    /// @dev Overriding this function to add the `nonReentrantView` modifier for consistency, even though it does not read from the state.
    function maxDeposit(address) public view virtual override nonReentrantView returns (uint256) {
        return _maxDeposit();
    }

    /// @notice Returns the maximum amount of the Vault shares that can be minted for the receiver.
    /// @dev Overriding this function to add the `nonReentrantView` modifier for consistency, even though it does not read from the state.
    function maxMint(address) public view virtual override nonReentrantView returns (uint256) {
        return _maxMint();
    }

    /// @dev Increase the total assets deposited.
    /// @dev See {IERC4626-_deposit}.
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override {
        super._deposit(_caller, _receiver, _assets, _shares);

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.totalAssetsDeposited += _assets;
    }

    /// @dev Withdraw needed amount from yield aggregator.
    ///      If cash reserve is not enough for withdraw, this function will loop through the withdrawal queue
    ///      and do withdraws till the amount is retrieved, or revert with `NotEnoughAssets()` error.
    /// @dev See {IERC4626-_withdraw}.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares)
        internal
        override
    {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        uint256 assetsRetrieved = IERC20(asset()).balanceOf(address(this));

        if (assetsRetrieved < _assets) {
            uint256 numStrategies = $.withdrawalQueue.length;
            for (uint256 i; i < numStrategies; ++i) {
                IERC4626 strategy = IERC4626($.withdrawalQueue[i]);

                if ($.strategies[address(strategy)].status != IEulerAggregationVault.StrategyStatus.Active) continue;

                uint256 underlyingBalance = strategy.maxWithdraw(address(this));
                uint256 desiredAssets = _assets - assetsRetrieved;
                uint256 withdrawAmount = (underlyingBalance >= desiredAssets) ? desiredAssets : underlyingBalance;

                // Do actual withdraw from strategy
                strategy.withdraw(withdrawAmount, address(this), address(this));

                // update withdrawAmount as in some cases we may not get that amount withdrawn.
                withdrawAmount = IERC20(asset()).balanceOf(address(this)) - assetsRetrieved;

                // Update allocated assets
                $.strategies[address(strategy)].allocated -= uint120(withdrawAmount);
                $.totalAllocated -= withdrawAmount;

                assetsRetrieved += withdrawAmount;

                if (assetsRetrieved >= _assets) {
                    break;
                }
            }
        }

        if (assetsRetrieved < _assets) {
            revert Errors.NotEnoughAssets();
        }

        $.totalAssetsDeposited -= _assets;

        super._withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    /// @dev Override _update hook to call IBalanceTracker.balanceTrackerHook().
    /// @dev This also re-implement the ERC20VotesUpgradeable._update() logic to use `_totalSupply()` instead of the nonReentrantView protected `totalSupply()`.
    /// @param _from Address sending the amount.
    /// @param _to Address receiving the amount.
    /// @param _value Amount to update.
    function _update(address _from, address _to, uint256 _value)
        internal
        override (ERC20VotesUpgradeable, ERC20Upgradeable)
    {
        /// call `_update()` on ERC20Upgradeable
        ERC20Upgradeable._update(_from, _to, _value);

        /// ERC20VotesUpgradeable `_update()`
        if (_from == address(0)) {
            uint256 supply = _totalSupply();
            uint256 cap = _maxSupply();
            if (supply > cap) {
                revert Errors.ERC20ExceededSafeSupply(supply, cap);
            }
        }
        _transferVotingUnits(_from, _to, _value);

        if (_from == _to) return;

        IBalanceTracker balanceTracker = IBalanceTracker(_balanceTrackerAddress());

        if ((_from != address(0)) && (_balanceForwarderEnabled(_from))) {
            balanceTracker.balanceTrackerHook(_from, _balanceOf(_from), false);
        }

        if ((_to != address(0)) && (_balanceForwarderEnabled(_to))) {
            balanceTracker.balanceTrackerHook(_to, _balanceOf(_to), false);
        }
    }

    /// @dev Override _msgSender() to recognize EVC authentication.
    /// @return address Sender address.
    function _msgSender() internal view virtual override (ContextUpgradeable, Shared) returns (address) {
        return Shared._msgSender();
    }

    /// @dev Internal conversion function (from assets to shares) with support for rounding direction.
    /// @param _assets Amount of assets.
    /// @param _rounding Rounding direction.
    /// @return Amount of shares.
    function _convertToShares(uint256 _assets, Math.Rounding _rounding) internal view override returns (uint256) {
        return _assets.mulDiv(_totalSupply() + 10 ** _decimalsOffset(), _totalAssets() + 1, _rounding);
    }

    /// @dev Internal conversion function (from shares to assets) with support for rounding direction.
    /// @param _shares Amount of shares.
    /// @param _rounding Rounding direction.
    /// @return Amount of assets.
    function _convertToAssets(uint256 _shares, Math.Rounding _rounding) internal view override returns (uint256) {
        return _shares.mulDiv(_totalAssets() + 1, _totalSupply() + 10 ** _decimalsOffset(), _rounding);
    }

    /// @dev Loop through strategies, harvest, aggregate positive and negative yield and account for net amount.
    /// @dev Loss socialization will be taken out from interest left + amount available to gulp first, if not enough, socialize on deposits.
    /// @dev Performance fee will only be applied on net positive yield across all strategies.
    /// @param _checkCooldown a boolean to indicate whether to check for cooldown period or not.
    function _harvest(bool _checkCooldown) private {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        if (_checkCooldown && ($.lastHarvestTimestamp + HARVEST_COOLDOWN >= block.timestamp)) {
            return;
        }

        uint256 totalPositiveYield;
        uint256 totalNegativeYield;
        for (uint256 i; i < $.withdrawalQueue.length; ++i) {
            (uint256 positiveYield, uint256 loss) = _executeHarvest($.withdrawalQueue[i]);

            totalPositiveYield += positiveYield;
            totalNegativeYield += loss;
        }

        // we should deduct loss before updating totalAllocated to not underflow
        if (totalNegativeYield > totalPositiveYield) {
            _deductLoss(totalNegativeYield - totalPositiveYield);
        } else if (totalNegativeYield < totalPositiveYield) {
            _accruePerformanceFee(totalPositiveYield - totalNegativeYield);
        }

        $.totalAllocated = $.totalAllocated + totalPositiveYield - totalNegativeYield;
        $.lastHarvestTimestamp = block.timestamp;

        _gulp();

        emit Events.Harvest($.totalAllocated, totalPositiveYield, totalNegativeYield);
    }

    /// @dev Execute harvest on a single strategy.
    /// @param _strategy Strategy address.
    /// @return Amount of positive yield if any, else 0.
    /// @return Amount of loss if any, else 0.
    function _executeHarvest(address _strategy) private returns (uint256, uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        uint120 strategyAllocatedAmount = $.strategies[_strategy].allocated;

        if (
            strategyAllocatedAmount == 0
                || $.strategies[_strategy].status != IEulerAggregationVault.StrategyStatus.Active
        ) return (0, 0);

        // Use `previewRedeem()` to get the actual assets amount, bypassing any limits or revert.
        uint256 aggregatorShares = IERC4626(_strategy).balanceOf(address(this));
        uint256 aggregatorAssets = IERC4626(_strategy).previewRedeem(aggregatorShares);
        $.strategies[_strategy].allocated = uint120(aggregatorAssets);

        uint256 positiveYield;
        uint256 loss;
        if (aggregatorAssets == strategyAllocatedAmount) {
            return (positiveYield, loss);
        } else if (aggregatorAssets > strategyAllocatedAmount) {
            positiveYield = aggregatorAssets - strategyAllocatedAmount;
        } else {
            loss = strategyAllocatedAmount - aggregatorAssets;
        }

        emit Events.ExecuteHarvest(_strategy, aggregatorAssets, strategyAllocatedAmount);

        return (positiveYield, loss);
    }

    /// @dev Accrue performace fee on aggregated harvested positive yield.
    /// @dev Fees will be minted as shares to fee recipient.
    /// @param _yield Net positive yield.
    function _accruePerformanceFee(uint256 _yield) private {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        address cachedFeeRecipient = $.feeRecipient;
        uint96 cachedPerformanceFee = $.performanceFee;

        if (cachedFeeRecipient == address(0) || cachedPerformanceFee == 0) return;

        // `feeAssets` will be rounded down to 0 if `yield * performanceFee < 1e18`.
        uint256 feeAssets = _yield.mulDiv(cachedPerformanceFee, 1e18, Math.Rounding.Floor);
        uint256 feeShares = _convertToShares(feeAssets, Math.Rounding.Floor);

        if (feeShares != 0) {
            // Move feeAssets from gulpable amount to totalAssetsDeposited to not dilute other depositors.
            $.totalAssetsDeposited += feeAssets;

            _mint(cachedFeeRecipient, feeShares);
        }

        emit Events.AccruePerformanceFee(cachedFeeRecipient, _yield, feeShares);
    }

    /// @notice Return the total amount of assets deposited, plus the accrued interest.
    /// @return total asset amount.
    function _totalAssets() private view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAssetsDeposited + _interestAccruedFromCache();
    }

    /// @dev Return max deposit amount.
    /// @return Max deposit amount.
    function _maxDeposit() private pure returns (uint256) {
        return type(uint256).max;
    }

    /// @dev Return max mint amount.
    /// @return Max mint amount.
    function _maxMint() private pure returns (uint256) {
        return type(uint256).max;
    }
}

contract AggregationVault is AggregationVaultModule {
    constructor(address _evc) Shared(_evc) {}
}
