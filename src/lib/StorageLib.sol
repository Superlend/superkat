// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @custom:storage-location erc7201:euler_aggregation_vault.storage.AggregationVault
struct AggregationVaultStorage {
    address evc;
    /// @dev Total amount of _asset deposited into FourSixTwoSixAgg contract
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
}
/// @custom:storage-location erc7201:euler_aggregation_vault.storage.BalanceForwarder

struct BalanceForwarderStorage {
    address balanceTracker;
    mapping(address => bool) isBalanceForwarderEnabled;
}
/// @custom:storage-location erc7201:euler_aggregation_vault.storage.Hooks

struct HooksStorage {
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
    // keccak256(abi.encode(uint256(keccak256("euler_aggregation_vault.storage.BalanceForwarder")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BalanceForwarderStorageLocation =
        0xf0af7cc3986d6cac468ac54c07f5f08359b3a00d65f8e2a86f2676ec79073f00;
    // keccak256(abi.encode(uint256(keccak256("euler_aggregation_vault.storage.Hooks")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant HooksStorageLocation = 0x7daefa3ee1567d8892b825e51ce683a058a5785193bcc2ca50940db02ccbf700;

    function _getAggregationVaultStorage() internal pure returns (AggregationVaultStorage storage $) {
        assembly {
            $.slot := AggregationVaultStorageLocation
        }
    }

    function _getBalanceForwarderStorage() internal pure returns (BalanceForwarderStorage storage $) {
        assembly {
            $.slot := BalanceForwarderStorageLocation
        }
    }

    function _getHooksStorage() internal pure returns (HooksStorage storage $) {
        assembly {
            $.slot := HooksStorageLocation
        }
    }
}
