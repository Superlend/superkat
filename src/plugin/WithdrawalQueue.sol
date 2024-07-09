// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IEulerAggregationVault} from "../core/interface/IEulerAggregationVault.sol";
import {IWithdrawalQueue} from "../core/interface/IWithdrawalQueue.sol";
// contracts
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

/// @title WithdrawalQueue plugin
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract manage the withdrawalQueue aray(add/remove strategy to the queue, re-order queue).
/// Also it handles finishing the withdraw execution flow through the `callWithdrawalQueue()` function
/// that will be called by the EulerAggregationVault.
contract WithdrawalQueue is AccessControlEnumerableUpgradeable, IWithdrawalQueue {
    error OutOfBounds();
    error SameIndexes();
    error NotEnoughAssets();
    error NotAuthorized();

    bytes32 public constant WITHDRAW_QUEUE_MANAGER = keccak256("WITHDRAW_QUEUE_MANAGER");
    bytes32 public constant WITHDRAW_QUEUE_MANAGER_ADMIN = keccak256("WITHDRAW_QUEUE_MANAGER_ADMIN");

    struct WithdrawalQueueStorage {
        address eulerAggregationVault;
        /// @dev An array of strategy addresses to withdraw from
        address[] withdrawalQueue;
    }

    // keccak256(abi.encode(uint256(keccak256("euler_aggregation_vault.storage.WithdrawalQueue")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueStorageLocation =
        0x8522ce6e5838588854909d348b0c9f7932eae519636e8e48e91e9b2639174600;

    event ReorderWithdrawalQueue(uint8 index1, uint8 index2);

    /// @notice Initialize WithdrawalQueue.
    /// @param _owner Aggregation vault owner.
    /// @param _eulerAggregationVault Address of aggregation vault.
    function init(address _owner, address _eulerAggregationVault) external initializer {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        $.eulerAggregationVault = _eulerAggregationVault;

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _setRoleAdmin(WITHDRAW_QUEUE_MANAGER, WITHDRAW_QUEUE_MANAGER_ADMIN);
    }

    /// @notice Add a strategy to withdrawal queue array.
    /// @dev Can only be called by the aggregation vault's address.
    /// @param _strategy Strategy address to add
    function addStrategyToWithdrawalQueue(address _strategy) external {
        _isCallerAggregationVault();

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        $.withdrawalQueue.push(_strategy);
    }

    /// @notice Remove a strategy from withdrawal queue array.
    /// @dev Can only be called by the aggregation vault's address.
    /// @param _strategy Strategy address to add.
    function removeStrategyFromWithdrawalQueue(address _strategy) external {
        _isCallerAggregationVault();

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        uint256 lastStrategyIndex = $.withdrawalQueue.length - 1;

        for (uint256 i = 0; i < lastStrategyIndex; ++i) {
            if ($.withdrawalQueue[i] == _strategy) {
                $.withdrawalQueue[i] = $.withdrawalQueue[lastStrategyIndex];

                break;
            }
        }

        $.withdrawalQueue.pop();
    }

    /// @notice Swap two strategies indexes in the withdrawal queue.
    /// @dev Can only be called by an address that have the WITHDRAW_QUEUE_MANAGER role.
    /// @param _index1 index of first strategy.
    /// @param _index2 index of second strategy.
    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) external onlyRole(WITHDRAW_QUEUE_MANAGER) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        uint256 length = $.withdrawalQueue.length;
        if (_index1 >= length || _index2 >= length) {
            revert OutOfBounds();
        }

        if (_index1 == _index2) {
            revert SameIndexes();
        }

        ($.withdrawalQueue[_index1], $.withdrawalQueue[_index2]) =
            ($.withdrawalQueue[_index2], $.withdrawalQueue[_index1]);

        emit ReorderWithdrawalQueue(_index1, _index2);
    }

    /// @notice Execute the withdraw initiated in the aggregation vault.
    /// @dev Can only be called by the aggregation vault's address.
    /// @param _caller Initiator's address of withdraw.
    /// @param _receiver Withdraw receiver address.
    /// @param _owner Shares's owner to burn.
    /// @param _assets Amount of asset to withdraw.
    /// @param _shares Amount of shares to burn.
    /// @param _availableAssets Amount of available asset in aggregation vault's cash reserve.
    function callWithdrawalQueue(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares,
        uint256 _availableAssets
    ) external {
        _isCallerAggregationVault();

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        address eulerAggregationVaultCached = $.eulerAggregationVault;

        if (_availableAssets < _assets) {
            uint256 numStrategies = $.withdrawalQueue.length;
            for (uint256 i; i < numStrategies; ++i) {
                IERC4626 strategy = IERC4626($.withdrawalQueue[i]);

                uint256 underlyingBalance = strategy.maxWithdraw(eulerAggregationVaultCached);
                uint256 desiredAssets = _assets - _availableAssets;
                uint256 withdrawAmount = (underlyingBalance > desiredAssets) ? desiredAssets : underlyingBalance;

                IEulerAggregationVault(eulerAggregationVaultCached).executeStrategyWithdraw(
                    address(strategy), withdrawAmount
                );

                // update assetsRetrieved
                _availableAssets += withdrawAmount;

                if (_availableAssets >= _assets) {
                    break;
                }
            }
        }

        // is this possible?
        if (_availableAssets < _assets) {
            revert NotEnoughAssets();
        }

        IEulerAggregationVault(eulerAggregationVaultCached).executeAggregationVaultWithdraw(
            _caller, _receiver, _owner, _assets, _shares
        );
    }

    /// @notice Get strategy address from withdrawal queue by index.
    /// @param _index Index to fetch.
    /// @return address Strategy address.
    function getWithdrawalQueueAtIndex(uint256 _index) external view returns (address) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        return $.withdrawalQueue[_index];
    }

    /// @notice Get the withdrawal queue array and it's length.
    /// @return withdrawalQueueMem The withdrawal queue array in memory.
    /// @return withdrawalQueueLengthCached An uint256 which is the length of the array.
    function getWithdrawalQueueArray() external view returns (address[] memory, uint256) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        uint256 withdrawalQueueLengthCached = $.withdrawalQueue.length;

        address[] memory withdrawalQueueMem = new address[](withdrawalQueueLengthCached);
        for (uint256 i; i < withdrawalQueueLengthCached; ++i) {
            withdrawalQueueMem[i] = $.withdrawalQueue[i];
        }

        return (withdrawalQueueMem, withdrawalQueueLengthCached);
    }

    /// @notice Return the withdrawal queue length.
    /// @return uint256 length.
    function withdrawalQueueLength() external view returns (uint256) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        return $.withdrawalQueue.length;
    }

    /// @dev Check if the msg.sender is the aggregation vault.
    function _isCallerAggregationVault() private view {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        if (msg.sender != $.eulerAggregationVault) revert NotAuthorized();
    }

    /// @dev Return storage pointer.
    /// @return $ WithdrawalQueueStorage storage struct.
    function _getWithdrawalQueueStorage() private pure returns (WithdrawalQueueStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueStorageLocation
        }
    }
}
