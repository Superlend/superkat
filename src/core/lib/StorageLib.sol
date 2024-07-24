// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";

/// @custom:storage-location erc7201:euler_aggregation_vault.storage.AggregationVault
struct AggregationVaultStorage {
    /// Total amount of _asset deposited into EulerAggregationVault contract
    uint256 totalAssetsDeposited;
    /// Total amount of _asset deposited across all strategies.
    uint256 totalAllocated;
    /// Total amount of allocation points across all strategies including the cash reserve.
    uint256 totalAllocationPoints;
    /// fee rate
    uint256 performanceFee;
    /// fee recipient address
    address feeRecipient;
    /// WithdrawalQueue plugin address
    address withdrawalQueue;
    /// Mapping between a strategy address and it's allocation config
    mapping(address => IEulerAggregationVault.Strategy) strategies;
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
    
    
    /// @dev storing the hooks target and kooked functions.
    uint256 hooksConfig;
}

library StorageLib {
    // keccak256(abi.encode(uint256(keccak256("euler_aggregation_vault.storage.AggregationVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AggregationVaultStorageLocation =
        0x7da5ece5aff94f3377324d715703a012d3253da37511270103c646f171c0aa00;

    /// @dev A function to return a pointer for the AggregationVaultStorageLocation.
    function _getAggregationVaultStorage() internal pure returns (AggregationVaultStorage storage $) {
        assembly {
            $.slot := AggregationVaultStorageLocation
        }
    }
}
