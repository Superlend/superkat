// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPermit2} from "../interface/IPermit2.sol";
// libs
import {RevertBytesLib} from "./RevertBytesLib.sol";
import {ErrorsLib as Errors} from "./ErrorsLib.sol";

/// @title SafePermit2Lib Library
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice The library provides helpers for ERC20 transfers based on Permit2.
/// Copied from https://github.com/euler-xyz/euler-vault-kit/blob/master/src/EVault/shared/lib/SafeERC20Lib.sol
library SafePermit2Lib {
    /// @dev Transfer from using Permit2. If `permit2 == address(0)` this will use the normale `ERC20.transferFrom()` call.
    function safePermitTransferFrom(IERC20 _token, address _from, address _to, uint256 _value, address _permit2)
        internal
    {
        bool success;
        bytes memory permit2Data;
        bytes memory transferData;

        if (_permit2 != address(0) && _value <= type(uint160).max) {
            // it's safe to down-cast value to uint160
            (success, permit2Data) =
                _permit2.call(abi.encodeCall(IPermit2.transferFrom, (_from, _to, uint160(_value), address(_token))));
        }

        if (!success) {
            (success, transferData) = _trySafeTransferFrom(_token, _from, _to, _value);
        }

        if (!success) revert Errors.SafeTransferFromFailed(permit2Data, transferData);
    }

    /// @dev If no code exists under the token address, the function will succeed. Yield aggregator ensures this is not the case in `init()`.
    function _trySafeTransferFrom(IERC20 _token, address _from, address _to, uint256 _value)
        private
        returns (bool, bytes memory)
    {
        (bool success, bytes memory data) =
            address(_token).call(abi.encodeCall(IERC20.transferFrom, (_from, _to, _value)));

        return _isEmptyOrTrueReturn(success, data) ? (true, bytes("")) : (false, data);
    }

    function _isEmptyOrTrueReturn(bool _callSuccess, bytes memory _data) private pure returns (bool) {
        return _callSuccess && (_data.length == 0 || (_data.length >= 32 && abi.decode(_data, (bool))));
    }
}
