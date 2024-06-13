// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title HooksLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `Hooks` custom type
/// @dev This is copied from https://github.com/euler-xyz/euler-vault-kit/blob/30b0b9e36b0a912fe430c7482e9b3bb12d180a4e/src/EVault/shared/types/Flags.sol
library HooksLib {
    /// @dev Are *all* of the Hooks in bitMask set?
    function isSet(uint32 _hookedFns, uint32 _fn) internal pure returns (bool) {
        return (_hookedFns & _fn) == _fn;
    }

    /// @dev Are *none* of the Hooks in bitMask set?
    function isNotSet(uint32 _hookedFns, uint32 _fn) internal pure returns (bool) {
        return (_hookedFns & _fn) == 0;
    }
}
