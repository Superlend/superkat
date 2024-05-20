// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Context} from "openzeppelin-contracts/utils/Context.sol";
import {ERC20, IERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626, IERC4626} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {EVCUtil, IEVC} from "ethereum-vault-connector/utils/EVCUtil.sol";
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

    // Roles
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

    /// @dev Total amount of _asset deposited into FourSixTwoSixAgg contract
    uint256 public totalAssetsDeposited;
    /// @dev Total amount of _asset deposited across all strategies.
    uint256 public totalAllocated;
    /// @dev Total amount of allocation points across all strategies including the cash reserve.
    uint256 public totalAllocationPoints;

    /// @dev An array of strategy addresses to withdraw from
    address[] public withdrawalQueue;

    /// @dev Mapping between strategy address and it's allocation config
    mapping(address => Strategy) internal strategies;

    struct ESRSlot {
        uint40 lastInterestUpdate;
        uint40 interestSmearEnd;
        uint168 interestLeft;
        uint8 locked;
    }

    /// @dev A struct that hold a strategy allocation's config
    /// allocated: amount of asset deposited into strategy
    /// allocationPoints number of points allocated to this strategy
    /// active: a boolean to indice if this strategy is active or not
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

    /// @dev Non reentrancy modifier for interest rate updates
    modifier nonReentrant() {
        if (esrSlot.locked == REENTRANCYLOCK__LOCKED) revert Reentrancy();

        esrSlot.locked = REENTRANCYLOCK__LOCKED;
        _;
        esrSlot.locked = REENTRANCYLOCK__UNLOCKED;
    }

    /// @dev Constructor
    /// @param _evc EVC address
    /// @param _asset Aggregator's asset address
    /// @param _name Aggregator's name
    /// @param _symbol Aggregator's symbol
    /// @param _initialCashAllocationPoints Initial points to be allocated to the cash reserve
    /// @param _initialStrategies An array of initial strategies addresses
    /// @param _initialStrategiesAllocationPoints An array of initial strategies allocation points
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
        totalAllocationPoints += _initialCashAllocationPoints;

        for (uint256 i; i < _initialStrategies.length; ++i) {
            strategies[_initialStrategies[i]] =
                Strategy({allocated: 0, allocationPoints: uint120(_initialStrategiesAllocationPoints[i]), active: true});

            totalAllocationPoints += _initialStrategiesAllocationPoints[i];
        }

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        // Setup role admins
        _setRoleAdmin(ALLOCATION_ADJUSTER_ROLE, ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE);
        _setRoleAdmin(WITHDRAW_QUEUE_REORDERER_ROLE, WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE);
        _setRoleAdmin(STRATEGY_ADDER_ROLE, STRATEGY_ADDER_ROLE_ADMIN_ROLE);
        _setRoleAdmin(STRATEGY_REMOVER_ROLE, STRATEGY_REMOVER_ROLE_ADMIN_ROLE);
    }

    /// @notice Get strategy params.
    /// @param _strategy strategy's address
    /// @return Strategy struct
    function getStrategy(address _strategy) external view returns (Strategy memory) {
        return strategies[_strategy];
    }

    /// @notice Return the withdrawal queue length.
    /// @return uint256 length
    function withdrawalQueueLength() external view returns (uint256) {
        return withdrawalQueue.length;
    }

    /// @notice Return the total amount of assets deposited, plus the accrued interest.
    /// @return uint256 total amount
    function totalAssets() public view override returns (uint256) {
        return totalAssetsDeposited + interestAccrued();
    }

    /// @notice get the total assets allocatable
    /// @dev the total assets allocatable is the amount of assets deposited into the aggregator + assets already deposited into strategies
    /// @return uint256 total assets
    function totalAssetsAllocatable() public view returns (uint256) {
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
        requireAccountStatusCheck(owner)
        returns (uint256 shares)
    {
        // Move interest to totalAssetsDeposited
        updateInterestAndReturnESRSlotCache();
        return super.withdraw(assets, receiver, owner);
    }

    /// @dev See {IERC4626-redeem}.
    /// @dev this function update the accrued interest
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

    /// @dev Increate the total assets deposited, and call IERC4626._deposit()
    /// @dev See {IERC4626-_deposit}.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        totalAssetsDeposited += assets;
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
        totalAssetsDeposited -= assets;

        uint256 assetsRetrieved = IERC20(asset()).balanceOf(address(this));
        for (uint256 i; i < withdrawalQueue.length; i++) {
            if (assetsRetrieved >= assets) {
                break;
            }

            IERC4626 strategy = IERC4626(withdrawalQueue[i]);

            _harvest(address(strategy));
            _gulp();

            Strategy memory strategyData = strategies[withdrawalQueue[i]];

            uint256 sharesBalance = strategy.balanceOf(address(this));
            uint256 underlyingBalance = strategy.convertToAssets(sharesBalance);

            uint256 desiredAssets = assets - assetsRetrieved;
            uint256 withdrawAmount = (underlyingBalance >= desiredAssets) ? desiredAssets : underlyingBalance;

            // Update allocated assets
            strategies[withdrawalQueue[i]].allocated = strategyData.allocated - uint120(withdrawAmount);
            totalAllocated -= withdrawAmount;

            // update assetsRetrieved
            assetsRetrieved += withdrawAmount;

            // Do actual withdraw from strategy
            strategy.withdraw(withdrawAmount, address(this), address(this));
        }

        if (assetsRetrieved < assets) {
            revert NotEnoughAssets();
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function gulp() public nonReentrant {
        _gulp();
    }

    function _gulp() internal {
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

    function rebalanceMultipleStrategies(address[] calldata _strategies) external nonReentrant {
        for (uint256 i; i < _strategies.length; ++i) {
            _rebalance(_strategies[i]);
        }
    }

    /// @notice Rebalance strategy allocation.
    /// @dev This function will first harvest yield, gulps and update interest.
    /// @dev If current allocation is greater than target allocation, the aggregator will withdraw the excess assets.
    ///      If current allocation is less than target allocation, the aggregator will:
    ///         - Try to deposit the delta, if the cash is not sufficient, deposit all the available cash
    ///         - If all the available cash is greater than the max deposit, deposit the max deposit
    function rebalance(address strategy) public nonReentrant {
        _rebalance(strategy);
    }

    function _rebalance(address _strategy) internal {
        if (_strategy == address(0)) {
            return; //nothing to rebalance as this is the cash reserve
        }

        // Harvest profits, also gulps and updates interest
        _harvest(_strategy);
        _gulp();

        Strategy memory strategyData = strategies[_strategy];

        uint256 totalAllocationPointsCache = totalAllocationPoints;
        uint256 totalAssetsAllocatableCache = totalAssetsAllocatable();
        uint256 targetAllocation =
            totalAssetsAllocatableCache * strategyData.allocationPoints / totalAllocationPointsCache;
        uint256 currentAllocation = strategyData.allocated;

        if (currentAllocation > targetAllocation) {
            // Withdraw
            uint256 toWithdraw = currentAllocation - targetAllocation;

            uint256 maxWithdraw = IERC4626(_strategy).maxWithdraw(address(this));
            if (toWithdraw > maxWithdraw) {
                toWithdraw = maxWithdraw;
            }

            IERC4626(_strategy).withdraw(toWithdraw, address(this), address(this));
            strategies[_strategy].allocated = uint120(currentAllocation - toWithdraw);
            totalAllocated -= toWithdraw;
        } else if (currentAllocation < targetAllocation) {
            // Deposit
            uint256 targetCash =
                totalAssetsAllocatableCache * strategies[address(0)].allocationPoints / totalAllocationPointsCache;
            uint256 currentCash = totalAssetsAllocatableCache - totalAllocated;

            // Calculate available cash to put in strategies
            uint256 cashAvailable = (currentCash > targetCash) ? currentCash - targetCash : 0;

            uint256 toDeposit = targetAllocation - currentAllocation;
            if (toDeposit > cashAvailable) {
                toDeposit = cashAvailable;
            }

            uint256 maxDeposit = IERC4626(_strategy).maxDeposit(address(this));
            if (toDeposit > maxDeposit) {
                toDeposit = maxDeposit;
            }

            if (toDeposit == 0) {
                return; // No cash to deposit
            }

            // Do required approval (safely) and deposit
            IERC20(asset()).safeApprove(_strategy, toDeposit);
            IERC4626(_strategy).deposit(toDeposit, address(this));
            strategies[_strategy].allocated = uint120(currentAllocation + toDeposit);
            totalAllocated += toDeposit;
        }
    }

    /// @notice Harvest positive yield.
    /// @param strategy address of strategy
    function harvest(address strategy) public nonReentrant {
        _harvest(strategy);

        _gulp();
    }

    function harvestMultipleStrategies(address[] calldata _strategies) external nonReentrant {
        for (uint256 i; i < _strategies.length; ++i) {
            _harvest(_strategies[i]);

            _gulp();
        }
    }

    function _harvest(address strategy) internal {
        Strategy memory strategyData = strategies[strategy];

        if (strategyData.allocated == 0) return;

        uint256 sharesBalance = IERC4626(strategy).balanceOf(address(this));
        uint256 underlyingBalance = IERC4626(strategy).convertToAssets(sharesBalance);

        if (underlyingBalance == strategyData.allocated) {
            return;
        } else if (underlyingBalance > strategyData.allocated) {
            // There's yield!
            uint256 yield = underlyingBalance - strategyData.allocated;
            strategies[strategy].allocated = uint120(underlyingBalance);
            totalAllocated += yield;
            // TODO possible performance fee
        } else {
            // TODO handle losses
            revert NegativeYield();
        }
    }

    /// @notice Adjust a certain strategy's allocation points.
    /// @dev Can only be called by an address that have the ALLOCATION_ADJUSTER_ROLE
    /// @param strategy address of strategy
    /// @param newPoints new strategy's points
    function adjustAllocationPoints(address strategy, uint256 newPoints)
        public
        nonReentrant
        onlyRole(ALLOCATION_ADJUSTER_ROLE)
    {
        Strategy memory strategyDataCache = strategies[strategy];
        uint256 totalAllocationPointsCache = totalAllocationPoints;

        if (!strategyDataCache.active) {
            revert InactiveStrategy();
        }

        strategies[strategy].allocationPoints = uint120(newPoints);

        totalAllocationPoints = (newPoints > strategyDataCache.allocationPoints)
            ? totalAllocationPointsCache + (newPoints - strategyDataCache.allocationPoints)
            : totalAllocationPointsCache - (strategyDataCache.allocationPoints - newPoints);
    }

    /// @notice Swap two strategies indexes in the withdrawal queue.
    /// @dev Can only be called by an address that have the WITHDRAW_QUEUE_REORDERER_ROLE.
    /// @param index1 index of first strategy
    /// @param index2 index of second strategy
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

    /// @notice Add new strategy with it's allocation points.
    /// @dev Can only be called by an address that have STRATEGY_ADDER_ROLE.
    /// @param strategy Address of the strategy
    /// @param allocationPoints Strategy's allocation points
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

    /// @notice Remove strategy and set its allocation points to zero.
    /// @dev This function does not pull funds, `harvest()` needs to be called to withdraw
    /// @dev Can only be called by an address that have the STRATEGY_REMOVER_ROLE
    /// @param strategy Address of the strategy
    function removeStrategy(address strategy) public nonReentrant onlyRole(STRATEGY_REMOVER_ROLE) {
        if (!strategies[strategy].active) {
            revert AlreadyRemoved();
        }

        strategies[strategy].active = false;
        totalAllocationPoints -= strategies[strategy].allocationPoints;
        strategies[strategy].allocationPoints = 0;

        // remove from withdrawalQueue
        uint256 lastStrategyIndex = withdrawalQueue.length - 1;

        for (uint256 i = 0; i <= lastStrategyIndex; i++) {
            if ((withdrawalQueue[i] == strategy) && (i != lastStrategyIndex)) {
                (withdrawalQueue[i], withdrawalQueue[lastStrategyIndex]) =
                    (withdrawalQueue[lastStrategyIndex], withdrawalQueue[i]);
            }
        }

        withdrawalQueue.pop();
    }

    /// @notice Return the accrued interest
    /// @return uint256 accrued interest
    function interestAccrued() public view returns (uint256) {
        return interestAccruedFromCache(esrSlot);
    }

    /// @dev Get accrued interest without updating it.
    /// @param esrSlotCache Cached esrSlot
    /// @return uint256 accrued interest
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

    /// @notice Return the ESRSlot struct
    /// @return ESRSlot struct
    function getESRSlot() public view returns (ESRSlot memory) {
        return esrSlot;
    }

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    ///      either msg.sender or the account authenticated by the EVC.
    /// @return The address of the message sender.
    function _msgSender() internal view override (Context, EVCUtil) returns (address) {
        return EVCUtil._msgSender();
    }
}
