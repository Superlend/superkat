// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerEarn, IEulerEarn} from "../src/EulerEarn.sol";
import {ConstantsLib} from "../src/lib/ConstantsLib.sol";

/// @title Script to add strategies to an existent Euler Earn vault.
contract Rebalance is ScriptUtil {
    error InputsMismatch();

    /// @dev EulerEarnFactory contract.
    EulerEarn eulerEarn;

    function run() public {
        // load JSON file
        string memory inputScriptFileName = "Rebalance_input.json";
        string memory json = getScriptFile(inputScriptFileName);

        uint256 userKey = vm.parseJsonUint(json, "userKey");
        address userAddress = vm.rememberKey(userKey);

        eulerEarn = EulerEarn(vm.parseJsonAddress(json, "eulerEarn"));
        address[] memory strategies = vm.parseJsonAddressArray(json, "strategies");

        vm.startBroadcast(userAddress);

        eulerEarn.rebalance(strategies);

        vm.stopBroadcast();
    }
}
