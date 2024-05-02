// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Context} from "openzeppelin-contracts/utils/Context.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {AccessControlEnumerable} from "openzeppelin-contracts/access/AccessControlEnumerable.sol";

// @note Do NOT use with fee on transfer tokens
// @note Do NOT use with rebasing tokens
// @note Based on https://github.com/euler-xyz/euler-vault-kit/blob/master/src/Synths/EulerSavingsRate.sol
// @note expired by Yearn v3 ❤️
// TODO addons for reward stream support
// TODO custom withdraw queue support
contract FourSixTwoSixAgg is EVCUtil, ERC4626, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    error Reentrancy();
    error ArrayLengthMismatch();
    error AddressesOutOfOrder();
    error DuplicateInitialStrategy();
    error InitialAllocationPointsZero();
    error NotEnoughAssets();
    error NegativeYield();
    error InactiveStrategy();
    error OutOfBounds();
    error SameIndexes();
    error InvalidStrategyAsset();
    error StrategyAlreadyExist();
    error AlreadyRemoved();

    uint8 internal constant REENTRANCYLOCK__UNLOCKED = 1;
    uint8 internal constant REENTRANCYLOCK__LOCKED = 2;

    // ROLES
    bytes32 public constant ALLOCATION_ADJUSTER_ROLE = keccak256("ALLOCATION_ADJUSTER_ROLE");
    bytes32 public constant ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE = keccak256("ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE");
    bytes32 public constant WITHDRAW_QUEUE_REORDERER_ROLE = keccak256("WITHDRAW_QUEUE_REORDERER_ROLE");
    bytes32 public constant WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE =
        keccak256("WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE");
    bytes32 public constant STRATEGY_ADDER_ROLE = keccak256("STRATEGY_ADDER_ROLE");
    bytes32 public constant STRATEGY_ADDER_ROLE_ADMIN_ROLE = keccak256("STRATEGY_ADDER_ROLE_ADMIN_ROLE");
    bytes32 public constant STRATEGY_REMOVER_ROLE = keccak256("STRATEGY_REMOVER_ROLE");
    bytes32 public constant STRATEGY_REMOVER_ROLE_ADMIN_ROLE = keccak256("STRATEGY_REMOVER_ROLE_ADMIN_ROLE");

    uint256 public constant INTEREST_SMEAR = 2 weeks;

    ESRSlot internal esrSlot;
    uint256 internal totalAssetsDeposited;

    uint256 totalAllocated;
    uint256 totalAllocationPoints;

    mapping(address => Strategy) internal strategies;
    address[] withdrawalQueue;

    struct ESRSlot {
        uint40 lastInterestUpdate;
        uint40 interestSmearEnd;
        uint168 interestLeft;
        uint8 locked;
    }

    struct Strategy {
        uint120 allocated;
        uint120 allocationPoints;
        bool active;
    }

    /// @notice Modifier to require an account status check on the EVC.
    /// @dev Calls `requireAccountStatusCheck` function from EVC for the specified account after the function body.
    /// @param account The address of the account to check.
    modifier requireAccountStatusCheck(address account) {
        _;
        evc.requireAccountStatusCheck(account);
    }

    modifier nonReentrant() {
        if (esrSlot.locked == REENTRANCYLOCK__LOCKED) revert Reentrancy();

        esrSlot.locked = REENTRANCYLOCK__LOCKED;
        _;
        esrSlot.locked = REENTRANCYLOCK__UNLOCKED;
    }

    constructor(
        IEVC _evc,
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints,
        address[] memory _initialStrategies,
        uint256[] memory _initialStrategiesAllocationPoints
    ) EVCUtil(address(_evc)) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) {
        esrSlot.locked = REENTRANCYLOCK__UNLOCKED;

        if (_initialStrategies.length != _initialStrategiesAllocationPoints.length) revert ArrayLengthMismatch();
        if (_initialCashAllocationPoints == 0) revert InitialAllocationPointsZero();

        strategies[address(0)] =
            Strategy({allocated: 0, allocationPoints: uint120(_initialCashAllocationPoints), active: true});

        for (uint256 i; i < _initialStrategies.length; ++i) {
            strategies[_initialStrategies[i]] =
                Strategy({allocated: 0, allocationPoints: uint120(_initialStrategiesAllocationPoints[i]), active: true});
        }

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        // Setup role admins
        _setRoleAdmin(ALLOCATION_ADJUSTER_ROLE, ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE);
        _setRoleAdmin(WITHDRAW_QUEUE_REORDERER_ROLE, WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE);
        _setRoleAdmin(STRATEGY_ADDER_ROLE, STRATEGY_ADDER_ROLE_ADMIN_ROLE);
        _setRoleAdmin(STRATEGY_REMOVER_ROLE, STRATEGY_REMOVER_ROLE_ADMIN_ROLE);
    }

    function totalAssets() public view override returns (uint256) {
        return totalAssetsDeposited + interestAccrued();
    }

    function totalAssetsAllocatable() public view returns (uint256) {
        // Whatever balance of asset this vault holds + whatever is allocated to strategies
        return IERC20(asset()).balanceOf(address(this)) + totalAllocated;
    }

    /// @notice Transfers a certain amount of tokens to a recipient.
    /// @param to The recipient of the transfer.
    /// @param amount The amount shares to transfer.
    /// @return A boolean indicating whether the transfer was successful.
    function transfer(address to, uint256 amount)
        public
        override (ERC20, IERC20)
        nonReentrant
        requireAccountStatusCheck(_msgSender())
        returns (bool)
    {
        return super.transfer(to, amount);
    }

    /// @notice Transfers a certain amount of tokens from a sender to a recipient.
    /// @param from The sender of the transfer.
    /// @param to The recipient of the transfer.
    /// @param amount The amount of shares to transfer.
    /// @return A boolean indicating whether the transfer was successful.
    function transferFrom(address from, address to, uint256 amount)
        public
        override (ERC20, IERC20)
        nonReentrant
        requireAccountStatusCheck(from)
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        return super.mint(assets, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        requireAccountStatusCheck(owner)
        returns (uint256 shares)
    {
        // Move interest to totalAssetsDeposited
        updateInterestAndReturnESRSlotCache();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        requireAccountStatusCheck(owner)
        returns (uint256 assets)
    {
        // Move interest to totalAssetsDeposited
        updateInterestAndReturnESRSlotCache();
        return super.redeem(shares, receiver, owner);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        totalAssetsDeposited += assets;
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        totalAssetsDeposited -= assets;

        uint256 assetsRetrieved = IERC20(asset()).balanceOf(address(this));
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            if (assetsRetrieved >= assets) {
                break;
            }

            Strategy memory strategyData = strategies[withdrawalQueue[i]];
            IERC4626 strategy = IERC4626(withdrawalQueue[i]);
            harvest(address(strategy));
            uint256 sharesBalance = strategy.balanceOf(address(this));
            uint256 underlyingBalance = strategy.convertToAssets(sharesBalance);

            uint256 desiredAssets = assets - assetsRetrieved;
            uint256 withdrawAmount;
            // We can take all we need 🎉
            if (underlyingBalance > desiredAssets) {
                withdrawAmount = desiredAssets;
            } else {
                // not enough but take all we can
                withdrawAmount = underlyingBalance;
            }

            // Update allocated assets
            strategies[withdrawalQueue[i]].allocated = strategyData.allocated - uint120(withdrawAmount);
            totalAllocated -= withdrawAmount;

            // Do actual withdraw from strategy
            strategy.withdraw(withdrawAmount, address(this), address(this));
        }

        if (assetsRetrieved < assets) {
            revert NotEnoughAssets();
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function gulp() public nonReentrant {
        ESRSlot memory esrSlotCache = updateInterestAndReturnESRSlotCache();
        uint256 toGulp = totalAssetsAllocatable() - totalAssetsDeposited - esrSlotCache.interestLeft;

        uint256 maxGulp = type(uint168).max - esrSlotCache.interestLeft;
        if (toGulp > maxGulp) toGulp = maxGulp; // cap interest, allowing the vault to function

        esrSlotCache.interestSmearEnd = uint40(block.timestamp + INTEREST_SMEAR);
        esrSlotCache.interestLeft += uint168(toGulp); // toGulp <= maxGulp <= max uint168

        // write esrSlotCache back to storage in a single SSTORE
        esrSlot = esrSlotCache;
    }

    function updateInterestAndReturnESRSlotCache() public returns (ESRSlot memory) {
        ESRSlot memory esrSlotCache = esrSlot;
        uint256 accruedInterest = interestAccruedFromCache(esrSlotCache);

        // it's safe to down-cast because the accrued interest is a fraction of interest left
        esrSlotCache.interestLeft -= uint168(accruedInterest);
        esrSlotCache.lastInterestUpdate = uint40(block.timestamp);
        // write esrSlotCache back to storage in a single SSTORE
        esrSlot = esrSlotCache;
        // Move interest accrued to totalAssetsDeposited
        totalAssetsDeposited += accruedInterest;

        return esrSlotCache;
    }

    function rebalance(address strategy) public nonReentrant {
        if (strategy == address(0)) {
            return; //nothing to rebalance as this is the cash reserve
        }

        // Harvest profits, also gulps and updates interest
        harvest(strategy);

        Strategy memory strategyData = strategies[strategy];
        uint256 totalAllocationPointsCache = totalAllocationPoints;
        uint256 totalAssetsAllocatableCache = totalAssetsAllocatable();
        uint256 targetAllocation =
            totalAssetsAllocatableCache * strategyData.allocationPoints / totalAllocationPointsCache;
        uint256 currentAllocation = strategyData.allocated;

        if (currentAllocation > targetAllocation) {
            // Withdraw
            // TODO handle maxWithdraw
            uint256 toWithdraw = currentAllocation - targetAllocation;

            uint256 maxWithdraw = IERC4626(strategy).maxWithdraw(address(this));
            if (toWithdraw > maxWithdraw) {
                toWithdraw = maxWithdraw;
            }

            IERC4626(strategy).withdraw(toWithdraw, address(this), address(this));
            strategies[strategy].allocated = uint120(targetAllocation); //TODO casting
            totalAllocated -= toWithdraw;
        } else if (currentAllocation < targetAllocation) {
            // Deposit
            uint256 targetCash =
                totalAssetsAllocatableCache * strategies[address(0)].allocationPoints / totalAllocationPointsCache;
            uint256 currentCash = totalAssetsAllocatableCache - totalAllocated;

            // Calculate available cash to put in strategies
            uint256 cashAvailable;
            if (targetCash > currentCash) {
                cashAvailable = targetCash - currentCash;
            } else {
                cashAvailable = 0;
            }

            uint256 toDeposit = targetAllocation - currentAllocation;
            if (toDeposit > cashAvailable) {
                toDeposit = cashAvailable;
            }

            uint256 maxDeposit = IERC4626(strategy).maxDeposit(address(this));
            if (toDeposit > maxDeposit) {
                toDeposit = maxDeposit;
            }

            if (toDeposit == 0) {
                return; // No cash to deposit
            }

            // Do required approval (safely) and deposit
            IERC20(asset()).safeApprove(strategy, toDeposit);
            IERC4626(strategy).deposit(toDeposit, address(this));
            strategies[strategy].allocated = uint120(currentAllocation + toDeposit);
            totalAllocated += toDeposit;
        }
    }

    // Todo possibly allow batch harvest
    function harvest(address strategy) public nonReentrant {
        Strategy memory strategyData = strategies[strategy];
        uint256 sharesBalance = IERC4626(strategy).balanceOf(address(this));
        uint256 underlyingBalance = IERC4626(strategy).convertToAssets(sharesBalance);

        // There's yield!
        if (underlyingBalance > strategyData.allocated) {
            uint256 yield = underlyingBalance - strategyData.allocated;
            strategies[strategy].allocated = uint120(underlyingBalance);
            totalAllocated += yield;
            // TODO possible performance fee
        } else {
            // TODO handle losses
            revert NegativeYield();
        }

        gulp();
    }

    function adjustAllocationPoints(address strategy, uint256 newPoints)
        public
        nonReentrant
        onlyRole(ALLOCATION_ADJUSTER_ROLE)
    {
        Strategy memory strategyData = strategies[strategy];
        uint256 totalAllocationPointsCache = totalAllocationPoints;

        if (strategyData.active = false) {
            revert InactiveStrategy();
        }

        strategies[strategy].allocationPoints = uint120(newPoints);
        if (newPoints > strategyData.allocationPoints) {
            uint256 diff = newPoints - strategyData.allocationPoints;
            totalAllocationPoints + totalAllocationPointsCache + diff;
        } else if (newPoints < strategyData.allocationPoints) {
            uint256 diff = strategyData.allocationPoints - newPoints;
            totalAllocationPoints = totalAllocationPointsCache - diff;
        }
    }

    function reorderWithdrawalQueue(uint8 index1, uint8 index2)
        public
        nonReentrant
        onlyRole(WITHDRAW_QUEUE_REORDERER_ROLE)
    {
        if (index1 >= withdrawalQueue.length || index2 >= withdrawalQueue.length) {
            revert OutOfBounds();
        }

        if (index1 == index2) {
            revert SameIndexes();
        }

        address temp = withdrawalQueue[index1];
        withdrawalQueue[index1] = withdrawalQueue[index2];
        withdrawalQueue[index2] = temp;
    }

    function addStrategy(address strategy, uint256 allocationPoints)
        public
        nonReentrant
        onlyRole(STRATEGY_ADDER_ROLE)
    {
        if (IERC4626(strategy).asset() != asset()) {
            revert InvalidStrategyAsset();
        }

        if (strategies[strategy].active) {
            revert StrategyAlreadyExist();
        }

        strategies[strategy] = Strategy({allocated: 0, allocationPoints: uint120(allocationPoints), active: true});

        totalAllocationPoints += allocationPoints;
        withdrawalQueue.push(strategy);
    }

    // remove strategy, sets its allocation points to zero. Does not pull funds, `harvest` needs to be called to withdraw
    function removeStrategy(address strategy) public nonReentrant onlyRole(STRATEGY_REMOVER_ROLE) {
        if (!strategies[strategy].active) {
            revert AlreadyRemoved();
        }

        strategies[strategy].active = false;
        totalAllocationPoints -= strategies[strategy].allocationPoints;
        strategies[strategy].allocationPoints = 0;

        // TODO remove from withdrawalQueue
    }

    function interestAccrued() public view returns (uint256) {
        return interestAccruedFromCache(esrSlot);
    }

    function interestAccruedFromCache(ESRSlot memory esrSlotCache) internal view returns (uint256) {
        // If distribution ended, full amount is accrued
        if (block.timestamp > esrSlotCache.interestSmearEnd) {
            return esrSlotCache.interestLeft;
        }

        // If just updated return 0
        if (esrSlotCache.lastInterestUpdate == block.timestamp) {
            return 0;
        }

        // Else return what has accrued
        uint256 totalDuration = esrSlotCache.interestSmearEnd - esrSlotCache.lastInterestUpdate;
        uint256 timePassed = block.timestamp - esrSlotCache.lastInterestUpdate;

        return esrSlotCache.interestLeft * timePassed / totalDuration;
    }

    function getESRSlot() public view returns (ESRSlot memory) {
        return esrSlot;
    }

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC.
    /// @return The address of the message sender.
    function _msgSender() internal view override (Context, EVCUtil) returns (address) {
        return EVCUtil._msgSender();
    }
}
