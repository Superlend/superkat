// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";
import {IBalanceTracker} from "reward-streams/interfaces/IBalanceTracker.sol";
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

    uint256 public constant HARVEST_COOLDOWN = 1 days;

    /// @notice Harvest all the strategies. Any positive yield should be gupled by calling gulp() after harvesting.
    /// @dev This function will loop through the strategies following the withdrawal queue order and harvest all.
    /// @dev Harvest positive and negative yields will be aggregated and only net amounts will be accounted.
    function harvest() public virtual nonReentrant {
        _updateInterestAccrued();

        _harvest(false);
    }

    /// @notice update accrued interest
    function updateInterestAccrued() public virtual nonReentrant {
        _updateInterestAccrued();
    }

    /// @notice gulp harvested positive yield
    function gulp() public virtual nonReentrant {
        _gulp();
    }

    /// @dev See {IERC4626-deposit}.
    /// @dev Call DEPOSIT hook if enabled.
    function deposit(uint256 _assets, address _receiver) public virtual override nonReentrant returns (uint256) {
        _callHooksTarget(DEPOSIT, _msgSender());

        return super.deposit(_assets, _receiver);
    }

    /// @dev See {IERC4626-mint}.
    /// @dev Call MINT hook if enabled.
    function mint(uint256 _shares, address _receiver) public virtual override nonReentrant returns (uint256) {
        _callHooksTarget(MINT, _msgSender());

        return super.mint(_shares, _receiver);
    }

    /// @dev See {IERC4626-withdraw}.
    /// @dev this function update the accrued interest and call WITHDRAW hook.
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 shares)
    {
        // Move interest to totalAssetsDeposited
        _updateInterestAccrued();

        _callHooksTarget(WITHDRAW, _msgSender());

        _harvest(true);

        return super.withdraw(_assets, _receiver, _owner);
    }

    /// @dev See {IERC4626-redeem}.
    /// @dev this function update the accrued interest and call WITHDRAW hook.
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 assets)
    {
        // Move interest to totalAssetsDeposited
        _updateInterestAccrued();

        _callHooksTarget(REDEEM, _msgSender());

        _harvest(true);

        return super.redeem(_shares, _receiver, _owner);
    }

    /// @notice Return the accrued interest
    /// @return uint256 accrued interest
    function interestAccrued() public view returns (uint256) {
        return _interestAccruedFromCache();
    }

    /// @notice Get saving rate data.
    /// @return uint40 last interest update timestamp.
    /// @return uint40 timestamp when interest smearing end.
    /// @return uint168 Amount of interest left to distribute.
    function getAggregationVaultSavingRate() public view returns (uint40, uint40, uint168) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return ($.lastInterestUpdate, $.interestSmearEnd, $.interestLeft);
    }

    /// @notice Get the total allocated amount.
    /// @return uint256 Total allocated.
    function totalAllocated() public view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAllocated;
    }

    /// @notice Get the total assets deposited into the aggregation vault.
    /// @return uint256 Total assets deposited.
    function totalAssetsDeposited() public view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAssetsDeposited;
    }

    /// @notice Get the latest harvest timestamp.
    /// @return uint256 Latest harvest timestamp.
    function lastHarvestTimestamp() public view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.lastHarvestTimestamp;
    }

    /// @notice get the total assets allocatable
    /// @dev the total assets allocatable is the amount of assets deposited into the aggregator + assets already deposited into strategies
    /// @return uint256 total assets
    function totalAssetsAllocatable() public view returns (uint256) {
        return _totalAssetsAllocatable();
    }

    /// @notice Return the total amount of assets deposited, plus the accrued interest.
    /// @return uint256 total amount
    function totalAssets() public view override returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAssetsDeposited + _interestAccruedFromCache();
    }

    /// @dev See {IERC4626-convertToShares}.
    function convertToShares(uint256 _assets) public view override returns (uint256) {
        return super.convertToShares(_assets);
    }

    /// @dev See {IERC4626-convertToAssets}.
    function convertToAssets(uint256 _shares) public view override returns (uint256) {
        return super.convertToAssets(_shares);
    }

    /// @dev See {IERC4626-maxWithdraw}.
    function maxWithdraw(address _owner) public view override returns (uint256) {
        return super.maxWithdraw(_owner);
    }

    /// @dev See {IERC4626-maxRedeem}.
    function maxRedeem(address _owner) public view override returns (uint256) {
        return super.maxRedeem(_owner);
    }

    /// @dev See {IERC4626-previewDeposit}.
    function previewDeposit(uint256 _assets) public view override returns (uint256) {
        return super.previewDeposit(_assets);
    }

    /// @dev See {IERC4626-previewMint}.
    function previewMint(uint256 _shares) public view override returns (uint256) {
        return super.previewMint(_shares);
    }

    /// @dev See {IERC4626-previewWithdraw}.
    function previewWithdraw(uint256 _assets) public view override returns (uint256) {
        return super.previewWithdraw(_assets);
    }

    /// @dev See {IERC4626-previewRedeem}.
    function previewRedeem(uint256 _shares) public view override returns (uint256) {
        return super.previewRedeem(_shares);
    }

    /// @dev See {IERC20Metadata-decimals}.
    function decimals() public view virtual override (ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /// @dev See {IERC4626-_deposit}.
    /// @dev Increase the total assets deposited.
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override {
        super._deposit(_caller, _receiver, _assets, _shares);

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        $.totalAssetsDeposited += _assets;
    }

    /// @dev See {IERC4626-_withdraw}.
    /// @dev If cash reserve is not enough for withdraw, this function will loop through the withdrawal queue
    ///      and do withdraws till the amount is retrieved, or revert with NotEnoughAssets() error.
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
                IERC4626(address(strategy)).withdraw(withdrawAmount, address(this), address(this));

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

    /// @dev Override _msgSender() to recognize EVC authentication.
    /// @return address Sender address.
    function _msgSender() internal view virtual override (ContextUpgradeable, Shared) returns (address) {
        return Shared._msgSender();
    }

    /// @dev Loop through strategies, aggregate positive and negative yield and account for net amounts.
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
    /// @return uint256 Amount of positive yield if any, else 0.
    /// @return uint256 Amount of loss if any, else 0.
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
}

contract AggregationVault is AggregationVaultModule {
    constructor(address _evc) Shared(_evc) {}
}
