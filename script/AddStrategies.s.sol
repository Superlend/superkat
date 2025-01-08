// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerEarn, IEulerEarn} from "../src/EulerEarn.sol";
import {ConstantsLib} from "../src/lib/ConstantsLib.sol";

/// @title Script to add strategies to an existent Euler Earn vault.
// to run:
// fill .env
// Run: source .env
// fil relevant json file
// Run: forge script ./script/AddStrategies.s.sol --rpc-url arbitrum --broadcast --slow -vvvvvv
contract AddStrategies is ScriptUtil {
    error InputsMismatch();

    /// @dev EulerEarnFactory contract.
    EulerEarn eulerEarn;

    function run() public {
        // load JSON file
        string memory inputScriptFileName = "AddStrategies_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        uint256 userKey = vm.parseJsonUint(json, ".userKey");
        address userAddress = vm.rememberKey(userKey);

        eulerEarn = EulerEarn(vm.parseJsonAddress(json, ".eulerEarn"));
        address[] memory strategies = vm.parseJsonAddressArray(json, ".strategies");
        uint256[] memory allocationPoints = vm.parseJsonUintArray(json, ".allocationPoints");

        require(strategies.length == allocationPoints.length, InputsMismatch());

        vm.startBroadcast(userAddress);

        for (uint256 i; i < strategies.length; i++) {
            eulerEarn.addStrategy(strategies[i], allocationPoints[i]);
        }

        vm.stopBroadcast();
    }
}
