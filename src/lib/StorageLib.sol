// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @custom:storage-location erc7201:euler_aggregation_vault.storage.AggregationVault
struct AggregationVaultStorage {
    /// @dev EVC address
    address evc;
    /// @dev Total amount of _asset deposited into AggregationLayerVault contract
    uint256 totalAssetsDeposited;
    /// @dev Total amount of _asset deposited across all strategies.
    uint256 totalAllocated;
    /// @dev Total amount of allocation points across all strategies including the cash reserve.
    uint256 totalAllocationPoints;
    /// @dev fee rate
    uint256 performanceFee;
    /// @dev fee recipient address
    address feeRecipient;
    /// @dev Withdrawal queue contract's address
    address withdrawalQueue;
    /// @dev Mapping between strategy address and it's allocation config
    mapping(address => Strategy) strategies;

    
    /// lastInterestUpdate: last timestamo where interest was updated.
    uint40 lastInterestUpdate;
    /// interestSmearEnd: timestamp when the smearing of interest end.
    uint40 interestSmearEnd;
    /// interestLeft: amount of interest left to smear.
    uint168 interestLeft;
    /// locked: if locked or not for update.
    uint8 locked;


    address balanceTracker;
    mapping(address => bool) isBalanceForwarderEnabled;

    
    /// @dev storing the hooks target and kooked functions.
    uint256 hooksConfig;
}

/// @dev A struct that hold a strategy allocation's config
/// allocated: amount of asset deposited into strategy
/// allocationPoints: number of points allocated to this strategy
/// active: a boolean to indice if this strategy is active or not
/// cap: an optional cap in terms of deposited underlying asset. By default, it is set to 0(not activated)
struct Strategy {
    uint120 allocated;
    uint120 allocationPoints;
    bool active;
    uint120 cap;
}

library StorageLib {
    // keccak256(abi.encode(uint256(keccak256("euler_aggregation_vault.storage.AggregationVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AggregationVaultStorageLocation =
        0x7da5ece5aff94f3377324d715703a012d3253da37511270103c646f171c0aa00;

    function _getAggregationVaultStorage() internal pure returns (AggregationVaultStorage storage $) {
        assembly {
            $.slot := AggregationVaultStorageLocation
        }
    }
}
