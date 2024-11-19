// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IEulerEarn} from "../interface/IEulerEarn.sol";

/// @custom:storage-location erc7201:euler.storage.EulerEarn
struct EulerEarnStorage {
    /// Total amount of _asset deposited into EulerEarn contract
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
    mapping(address => IEulerEarn.Strategy) strategies;
    /// An array of strategy addresses to withdraw from
    address[] withdrawalQueue;

    // 1 slot: 40 + 40 + 168 + 8
    /// lastInterestUpdate: last timestamp where interest was updated.
    uint40 lastInterestUpdate;
    /// interestSmearEnd: timestamp when the smearing of interest end.
    uint40 interestSmearEnd;
    /// interestLeft: amount of interest left to smear.
    uint168 interestLeft;
    /// locked: lock for re-entrancy guard.
    uint8 locked;
    
    /// @dev The period where the harvested positive yield is distributed as interest.
    uint256 smearingPeriod;

    /// A mapping to check if a user address enabled balance forwarding for reward streams integration.
    mapping(address => bool) isBalanceForwarderEnabled;
    
    // 1 slot: 160 + 32 + 40
    /// storing the hooks target and hooked functions.
    address hooksTarget;
    uint32 hookedFns;

    /// Last harvest timestamp, this is only updated when a harvest is explicitly called,
    /// Or when a harvest is executed while rebalancing, withdrawing or redeeming.
    uint40 lastHarvestTimestamp;
}

library StorageLib {
    // keccak256(abi.encode(uint256(keccak256("euler.storage.EulerEarn")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EulerEarnStorageLocation =
        0x557a0cdd38e5249281b5bc89e23dd8e4f8f0223d657d77792700289d81047f00;

    /// @dev A function to return a pointer for the EulerEarnStorageLocation.
    function _getEulerEarnStorage() internal pure returns (EulerEarnStorage storage $) {
        assembly {
            $.slot := EulerEarnStorageLocation
        }
    }
}
