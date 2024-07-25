// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";
// contracts
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Shared} from "../common/Shared.sol";
// libs
import {StorageLib as Storage, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";

abstract contract WithdrawalQueueModule is Shared {
    // bytes32 public constant WITHDRAW_QUEUE_MANAGER = keccak256("WITHDRAW_QUEUE_MANAGER");
    // bytes32 public constant WITHDRAW_QUEUE_MANAGER_ADMIN = keccak256("WITHDRAW_QUEUE_MANAGER_ADMIN");

    event ReorderWithdrawalQueue(uint8 index1, uint8 index2);

    /// @notice Swap two strategies indexes in the withdrawal queue.
    /// @dev Can only be called by an address that have the WITHDRAW_QUEUE_MANAGER role.
    /// @param _index1 index of first strategy.
    /// @param _index2 index of second strategy.
    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) public virtual nonReentrant {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        uint256 length = $.withdrawalQueue.length;
        if (_index1 >= length || _index2 >= length) {
            revert Errors.OutOfBounds();
        }

        if (_index1 == _index2) {
            revert Errors.SameIndexes();
        }

        ($.withdrawalQueue[_index1], $.withdrawalQueue[_index2]) =
            ($.withdrawalQueue[_index2], $.withdrawalQueue[_index1]);

        emit ReorderWithdrawalQueue(_index1, _index2);
    }

    /// @notice Return the withdrawal queue length.
    /// @return uint256 length.
    function withdrawalQueue() public view virtual returns (address[] memory) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.withdrawalQueue;
    }
}

contract WithdrawalQueue is WithdrawalQueueModule {}
