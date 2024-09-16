// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// libs
import {ErrorsLib as Errors} from "./ErrorsLib.sol";

/// @title RevertBytesLib Library
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice The library provides a helper function for bubbling up errors
library RevertBytesLib {
    /// @dev Revert with call error or EmptyError
    /// @param _errorMsg call revert message
    function revertBytes(bytes memory _errorMsg) internal pure {
        if (_errorMsg.length > 0) {
            assembly {
                revert(add(32, _errorMsg), mload(_errorMsg))
            }
        }

        revert Errors.EmptyError();
    }
}
