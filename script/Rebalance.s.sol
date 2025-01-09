// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerEarn} from "../src/EulerEarn.sol";

/// @title Script to add strategies to an existent Euler Earn vault.
// to run:
// fill .env
// Run: source .env
// fil relevant json file
// Run: forge script ./script/Rebalance.s.sol --rpc-url arbitrum --broadcast --slow -vvvvvv
contract Rebalance is ScriptUtil {
    error InputsMismatch();

    /// @dev EulerEarnFactory contract.
    EulerEarn eulerEarn;

    function run() public {
        // load wallet
        uint256 userKey = vm.envUint("WALLET_PRIVATE_KEY");
        address userAddress = vm.rememberKey(userKey);

        // load JSON file
        string memory inputScriptFileName = "Rebalance_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        eulerEarn = EulerEarn(vm.parseJsonAddress(json, ".eulerEarn"));
        address[] memory strategies = vm.parseJsonAddressArray(json, ".strategies");

        vm.startBroadcast(userAddress);

        eulerEarn.rebalance(strategies);

        vm.stopBroadcast();
    }
}
