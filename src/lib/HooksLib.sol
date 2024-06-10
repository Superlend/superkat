// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title HooksLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `Hooks` custom type
library HooksLib {
    /// @dev Are *all* of the Hooks in bitMask set?
    function isSet(HooksType self, uint32 bitMask) internal pure returns (bool) {
        return (HooksType.unwrap(self) & bitMask) == bitMask;
    }

    /// @dev Are *none* of the Hooks in bitMask set?
    function isNotSet(HooksType self, uint32 bitMask) internal pure returns (bool) {
        return (HooksType.unwrap(self) & bitMask) == 0;
    }

    function toUint32(HooksType self) internal pure returns (uint32) {
        return HooksType.unwrap(self);
    }
}

type HooksType is uint32;