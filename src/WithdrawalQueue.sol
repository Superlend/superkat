// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// external dep
import {AccessControlEnumerableUpgradeable} from "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
// internal dep
import {IFourSixTwoSixAgg} from "./interface/IFourSixTwoSixAgg.sol";

contract WithdrawalQueue is AccessControlEnumerableUpgradeable {
    error OutOfBounds();
    error SameIndexes();
    error NotEnoughAssets();

    bytes32 public constant WITHDRAW_QUEUE_MANAGER = keccak256("WITHDRAW_QUEUE_MANAGER");
    bytes32 public constant WITHDRAW_QUEUE_MANAGER_ADMIN = keccak256("WITHDRAW_QUEUE_MANAGER_ADMIN");

    address public eulerAggregationVault;

    /// @dev An array of strategy addresses to withdraw from
    address[] public withdrawalQueue;

    bool private isInitialized_;

    event ReorderWithdrawalQueue(uint8 index1, uint8 index2);

    function initWithdrawalQueue(address _owner, address[] calldata _initialStrategies) external {
        if (isInitialized_) revert();

        isInitialized_ = true;

        for (uint256 i; i < _initialStrategies.length; ++i) {
            withdrawalQueue.push(_initialStrategies[i]);
        }

        eulerAggregationVault = msg.sender;

        // Setup DEFAULT_ADMIN
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _setRoleAdmin(WITHDRAW_QUEUE_MANAGER, WITHDRAW_QUEUE_MANAGER_ADMIN);
    }

    // TODO: add access control
    function addStrategyToWithdrawalQueue(address _strategy) external {
        withdrawalQueue.push(_strategy);
    }

    // TODO: add access control
    function removeStrategyFromWithdrawalQueue(address _strategy) external {
        uint256 lastStrategyIndex = withdrawalQueue.length - 1;

        for (uint256 i = 0; i < lastStrategyIndex; ++i) {
            if (withdrawalQueue[i] == _strategy) {
                withdrawalQueue[i] = withdrawalQueue[lastStrategyIndex];

                break;
            }
        }

        withdrawalQueue.pop();
    }

    // TODO: add access control
    function executeWithdrawFromQueue(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 availableAssets
    ) external {
        uint256 numStrategies = withdrawalQueue.length;
        for (uint256 i; i < numStrategies; ++i) {
            IERC4626 strategy = IERC4626(withdrawalQueue[i]);

            IFourSixTwoSixAgg(eulerAggregationVault).harvest(address(strategy));

            uint256 underlyingBalance = strategy.maxWithdraw(eulerAggregationVault);
            uint256 desiredAssets = assets - availableAssets;
            uint256 withdrawAmount = (underlyingBalance > desiredAssets) ? desiredAssets : underlyingBalance;

            IFourSixTwoSixAgg(eulerAggregationVault).withdrawFromStrategy(address(strategy), withdrawAmount);

            // update assetsRetrieved
            availableAssets += withdrawAmount;

            if (availableAssets >= assets) {
                break;
            }
        }

        if (availableAssets < assets) {
            revert NotEnoughAssets();
        }

        IFourSixTwoSixAgg(eulerAggregationVault).executeWithdrawFromReserve(caller, receiver, owner, assets, shares);
    }

    /// @notice Swap two strategies indexes in the withdrawal queue.
    /// @dev Can only be called by an address that have the WITHDRAW_QUEUE_MANAGER.
    /// @param _index1 index of first strategy
    /// @param _index2 index of second strategy
    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) external onlyRole(WITHDRAW_QUEUE_MANAGER) {
        uint256 length = withdrawalQueue.length;
        if (_index1 >= length || _index2 >= length) {
            revert OutOfBounds();
        }

        if (_index1 == _index2) {
            revert SameIndexes();
        }

        (withdrawalQueue[_index1], withdrawalQueue[_index2]) = (withdrawalQueue[_index2], withdrawalQueue[_index1]);

        emit ReorderWithdrawalQueue(_index1, _index2);
    }

    /// @notice Return the withdrawal queue length.
    /// @return uint256 length
    function withdrawalQueueLength() external view returns (uint256) {
        return withdrawalQueue.length;
    }
}
