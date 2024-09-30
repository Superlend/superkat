// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// contracts
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
// libs
import {StorageLib as Storage, EulerEarnStorage} from "../lib/StorageLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";
import {ConstantsLib as Constants} from "../lib/ConstantsLib.sol";
import {RevertBytesLib} from "../lib/RevertBytesLib.sol";

/// @title Shared contract
/// @dev Have common functions that is used in different contracts.
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract Shared is EVCUtil {
    /// @dev Non-reentracy protection for state-changing functions.
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /// @dev Non-reentracy protection for view functions.
    modifier nonReentrantView() {
        _nonReentrantViewBefore();
        _;
    }

    /// @dev Address of balance tracker contract for reward streams integration.
    address internal immutable balanceTracker;
    /// @dev Permit2 contract address.
    address public immutable permit2;
    /// @dev A boolean to whether execute the harvest cooldown period check or not.
    ///      This is meant to be set to `False` when deploying on L2 to explicitly harvest on every withdraw/redeem.
    bool public immutable isHarvestCoolDownCheckOn;

    /// @dev Integrations
    struct IntegrationsParams {
        address evc;
        address balanceTracker;
        address permit2;
        bool isHarvestCoolDownCheckOn;
    }

    /// @dev Constructor.
    /// @param _integrationsParams IntegrationsParams struct.
    constructor(IntegrationsParams memory _integrationsParams) EVCUtil(_integrationsParams.evc) {
        balanceTracker = _integrationsParams.balanceTracker;
        permit2 = _integrationsParams.permit2;
        isHarvestCoolDownCheckOn = _integrationsParams.isHarvestCoolDownCheckOn;
    }

    /// @dev Deduct _lossAmount from the not-distributed amount, if not enough, socialize loss.
    /// @dev The not distributed amount is amount available to gulp + interest left.
    /// @param _lossAmount Amount lost.
    function _deductLoss(uint256 _lossAmount) internal {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        uint256 totalAssetsDepositedCache = $.totalAssetsDeposited;
        uint256 totalNotDistributed = _totalAssetsAllocatable() - totalAssetsDepositedCache;

        // set interestLeft to zero, will be updated to the right value during _gulp()
        $.interestLeft = 0;
        if (_lossAmount > totalNotDistributed) {
            unchecked {
                _lossAmount -= totalNotDistributed;
            }

            // socialize the loss
            $.totalAssetsDeposited = totalAssetsDepositedCache - _lossAmount;

            emit Events.DeductLoss(_lossAmount);
        }
    }

    /// @dev Checks whether a hook has been installed for the function and if so, invokes the hook target.
    /// @param _fn Function to call the hook for.
    /// @param _caller Caller's address.
    function _callHooksTarget(uint32 _fn, address _caller) internal {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        (address target, uint32 hookedFns) = ($.hooksTarget, $.hookedFns);

        if ((hookedFns & _fn) == 0) return;

        (bool success, bytes memory data) = target.call(abi.encodePacked(msg.data, _caller));

        if (!success) RevertBytesLib.revertBytes(data);
    }

    /// @dev gulp positive yield into interest left amd update accrued interest.
    function _gulp() internal {
        _updateInterestAccrued();

        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        uint168 interestLeftCached = $.interestLeft;
        uint256 toGulp = _totalAssetsAllocatable() - $.totalAssetsDeposited - interestLeftCached;
        if (toGulp == 0) return;

        uint256 maxGulp = type(uint168).max - interestLeftCached;
        if (toGulp > maxGulp) toGulp = maxGulp; // cap interest, allowing the vault to function

        interestLeftCached += uint168(toGulp); // toGulp <= maxGulp <= max uint168
        $.lastInterestUpdate = uint40(block.timestamp);
        $.interestSmearEnd = uint40(block.timestamp + Constants.INTEREST_SMEAR);
        $.interestLeft = interestLeftCached;

        emit Events.Gulp(interestLeftCached, $.interestSmearEnd);
    }

    /// @dev update accrued interest.
    function _updateInterestAccrued() internal {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        uint168 interestLeftCached = $.interestLeft;
        uint256 accruedInterest = _interestAccruedFromCache(interestLeftCached);

        if (accruedInterest > 0) {
            // it's safe to down-cast because the accrued interest is a fraction of interest left
            interestLeftCached -= uint168(accruedInterest);
            $.interestLeft = interestLeftCached;
            $.lastInterestUpdate = uint40(block.timestamp);

            // Move interest accrued to totalAssetsDeposited
            $.totalAssetsDeposited += accruedInterest;

            emit Events.InterestUpdated(accruedInterest, interestLeftCached);
        }
    }

    /// @dev Get accrued interest without updating it.
    /// @return Accrued interest.
    function _interestAccruedFromCache(uint168 _interestLeft) internal view returns (uint256) {
        // do not update interest
        if (_totalSupply() == 0) return 0;

        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        uint40 interestSmearEndCached = $.interestSmearEnd;
        // If distribution ended, full amount is accrued
        if (block.timestamp >= interestSmearEndCached) {
            return _interestLeft;
        }

        uint40 lastInterestUpdateCached = $.lastInterestUpdate;
        // If just updated return 0
        if (lastInterestUpdateCached == block.timestamp) {
            return 0;
        }

        // Else return what has accrued
        uint256 totalDuration = interestSmearEndCached - lastInterestUpdateCached;
        uint256 timePassed = block.timestamp - lastInterestUpdateCached;

        return _interestLeft * timePassed / totalDuration;
    }

    /// @dev Return total assets allocatable.
    /// @dev The total assets allocatable is the current balanceOf + total amount already allocated.
    /// @return total assets allocatable.
    function _totalAssetsAllocatable() internal view returns (uint256) {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        return IERC20(_asset()).balanceOf(address(this)) + $.totalAllocated;
    }

    /// @dev Override for _msgSender() to use the EVC authentication.
    /// @return Sender address.
    function _msgSender() internal view virtual override (EVCUtil) returns (address) {
        return EVCUtil._msgSender();
    }

    /// @dev Retrieves boolean indicating if the account opted in to forward balance changes to the rewards contract
    /// @param _account Address to query
    /// @return True if balance forwarder is enabled
    function _balanceForwarderEnabled(address _account) internal view returns (bool) {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        return $.isBalanceForwarderEnabled[_account];
    }

    /// @dev Read `_balances` from storage.
    /// @return _account balance.
    function _balanceOf(address _account) internal view returns (uint256) {
        ERC20Upgradeable.ERC20Storage storage $ = _getInheritedERC20Storage();
        return $._balances[_account];
    }

    /// @dev Read `_totalSupply` from storage.
    /// @return Euler Earn total supply.
    function _totalSupply() internal view returns (uint256) {
        ERC20Upgradeable.ERC20Storage storage $ = _getInheritedERC20Storage();
        return $._totalSupply;
    }

    function _asset() internal view returns (address) {
        ERC4626Upgradeable.ERC4626Storage storage $ = _getInheritedERC4626Storage();
        return address($._asset);
    }

    /// @dev Used by the nonReentrant before returning the execution flow to the original function.
    function _nonReentrantBefore() private {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        require($.locked != Constants.REENTRANCYLOCK__LOCKED, Errors.Reentrancy());

        $.locked = Constants.REENTRANCYLOCK__LOCKED;
    }

    /// @dev Used by the nonReentrant after returning the execution flow to the original function.
    function _nonReentrantAfter() private {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        $.locked = Constants.REENTRANCYLOCK__UNLOCKED;
    }

    /// @dev Used by the nonReentrantView before returning the execution flow to the original function.
    function _nonReentrantViewBefore() private view {
        EulerEarnStorage storage $ = Storage._getEulerEarnStorage();

        if ($.locked == Constants.REENTRANCYLOCK__LOCKED) {
            // The hook target is allowed to bypass the RO-reentrancy lock.
            require(msg.sender == $.hooksTarget || msg.sender == address(this), Errors.ViewReentrancy());
        }
    }

    /// @dev Return ERC20StorageLocation pointer.
    ///      This is copied from ERC20Upgradeable OZ implementation to be able to access ERC20 storage and override functions.
    ///      keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC4626")) - 1)) & ~bytes32(uint256(0xff))
    function _getInheritedERC4626Storage() private pure returns (ERC4626Upgradeable.ERC4626Storage storage $) {
        assembly {
            $.slot := 0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00
        }
    }

    /// @dev Return ERC20StorageLocation pointer.
    ///      This is copied from ERC20Upgradeable OZ implementation to be able to access ERC20 storage and override functions.
    ///      keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
    function _getInheritedERC20Storage() private pure returns (ERC20Upgradeable.ERC20Storage storage $) {
        assembly {
            $.slot := 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00
        }
    }
}
