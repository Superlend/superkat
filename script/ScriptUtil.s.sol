// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

contract ScriptUtil is Script {
    function getScriptFilePath(string memory jsonFile) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/script/", jsonFile);
    }

    function getScriptFile(string memory jsonFile) internal view returns (string memory) {
        return vm.readFile(getScriptFilePath(jsonFile));
    }
}
