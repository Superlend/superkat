// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IYieldAggregator} from "../interface/IYieldAggregator.sol";

/// @custom:storage-location erc7201:euler_yield_aggregator.storage.YieldAggregator
struct YieldAggregatorStorage {
    /// Total amount of _asset deposited into YieldAggregator contract
    uint256 totalAssetsDeposited;
    /// Total amount of _asset deposited across all strategies.
    uint256 totalAllocated;
    /// Total amount of allocation points across all strategies including the cash reserve.
    uint256 totalAllocationPoints;
    // 1 slot: 96 + 160
    /// fee rate
    uint96 performanceFee;
    /// fee recipient address
    address feeRecipient;
    /// Mapping between a strategy address and it's allocation config
    mapping(address => IYieldAggregator.Strategy) strategies;
    /// @dev An array of strategy addresses to withdraw from
    address[] withdrawalQueue;

    // 1 slot: 40 + 40 + 168 + 8
    /// lastInterestUpdate: last timestamp where interest was updated.
    uint40 lastInterestUpdate;
    /// interestSmearEnd: timestamp when the smearing of interest end.
    uint40 interestSmearEnd;
    /// interestLeft: amount of interest left to smear.
    uint168 interestLeft;
    /// locked: if locked or not for update.
    uint8 locked;
    
    
    /// Address of balance tracker contract for reward streams integration.
    address balanceTracker;
    /// A mapping to check if a user address enabled balance forwarding for reward streams integration.
    mapping(address => bool) isBalanceForwarderEnabled;
    
    // 1 slot: 160 + 32 + 40
    /// @dev storing the hooks target and hooked functions.
    address hooksTarget;
    uint32 hookedFns;

    /// @dev Last harvest timestamp
    uint40 lastHarvestTimestamp;
}

library StorageLib {
    // keccak256(abi.encode(uint256(keccak256("euler_yield_aggregator.storage.YieldAggregator")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant YieldAggregatorStorageLocation =
        0xac0b522cbeffc7768e2fa69372227b3c347a154761ba132cbe29d024b3f8eb00;

    /// @dev A function to return a pointer for the YieldAggregatorStorageLocation.
    function _getYieldAggregatorStorage() internal pure returns (YieldAggregatorStorage storage $) {
        assembly {
            $.slot := YieldAggregatorStorageLocation
        }
    }
}
