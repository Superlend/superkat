// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title AmountCapLib
/// @dev This is copied from https://github.com/euler-xyz/euler-vault-kit/blob/20973e1dd2037d26e8dea2f4ab2849e53a77855e/src/EVault/shared/types/AmountCap.sol
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `AmountCap` custom type
/// @dev AmountCaps are 16-bit decimal floating point values:
/// * The least significant 6 bits are the exponent
/// * The most significant 10 bits are the mantissa, scaled by 100
/// * The special value of 0 means limit is not set
///   * This is so that uninitialized storage implies no limit
///   * For an actual cap value of 0, use a zero mantissa and non-zero exponent
library AmountCapLib {
    /// @dev Resolve a cap amount from AmountCap type.
    /// @return uint256 Strategy cap amount.
    function resolve(AmountCap self) internal pure returns (uint256) {
        uint256 amountCap = AmountCap.unwrap(self);

        if (amountCap == 0) return type(uint256).max;

        unchecked {
            // Cannot overflow because this is less than 2**256:
            //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }

    ///
    function toRawUint16(AmountCap self) internal pure returns (uint16) {
        return AmountCap.unwrap(self);
    }
}

type AmountCap is uint16;
