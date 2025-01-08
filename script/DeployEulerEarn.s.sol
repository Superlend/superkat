// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerEarn} from "../src/EulerEarn.sol";
import {EulerEarnFactory} from "../src/EulerEarnFactory.sol";
import {ConstantsLib} from "../src/lib/ConstantsLib.sol";

/// @title Script to deploy new Euler Earn vault by calling factory, granting all roles and their admin roles to deployer address.
// to run:
// fill .env
// Run: source .env
// fil relevant json file
// Run: forge script ./script/DeployEulerEarn.s.sol --rpc-url arbitrum --broadcast --slow -vvvvvv
contract DeployEulerEarn is ScriptUtil {
    /// @dev EulerEarnFactory contract.
    EulerEarnFactory eulerEulerEarnFactory;

    function run() public returns (address) {
        // load JSON file
        string memory inputScriptFileName = "DeployEulerEarn_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        uint256 userKey = vm.parseJsonUint(json, ".userKey");
        address userAddress = vm.rememberKey(userKey);

        eulerEulerEarnFactory = EulerEarnFactory(vm.parseJsonAddress(json, ".eulerEulerEarnFactory"));
        address asset = vm.parseJsonAddress(json, ".asset");
        string memory name = vm.parseJsonString(json, ".name");
        string memory symbol = vm.parseJsonString(json, ".symbol");
        uint256 initialCashAllocationPoints = vm.parseJsonUint(json, ".initialCashAllocationPoints");
        uint24 smearingPeriod = uint24(vm.parseJsonUint(json, ".smearingPeriod"));

        vm.startBroadcast(userAddress);

        EulerEarn eulerEarnVault = EulerEarn(
            eulerEulerEarnFactory.deployEulerEarn(asset, name, symbol, initialCashAllocationPoints, smearingPeriod)
        );

        // grant admin roles to deployer
        eulerEarnVault.grantRole(ConstantsLib.GUARDIAN_ADMIN, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.STRATEGY_OPERATOR_ADMIN, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.EULER_EARN_MANAGER_ADMIN, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.REBALANCER_ADMIN, userAddress);

        // grant roles to deployer
        eulerEarnVault.grantRole(ConstantsLib.GUARDIAN, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.STRATEGY_OPERATOR, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.EULER_EARN_MANAGER, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER, userAddress);
        eulerEarnVault.grantRole(ConstantsLib.REBALANCER, userAddress);

        vm.stopBroadcast();

        return address(eulerEarnVault);
    }
}
