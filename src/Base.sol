// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {StorageLib, AggregationVaultStorage} from "./lib/StorageLib.sol";
import {ErrorsLib} from "./lib/ErrorsLib.sol";
import {IEVC} from "ethereum-vault-connector/utils/EVCUtil.sol";

contract Base {
    uint8 internal constant REENTRANCYLOCK__UNLOCKED = 1;
    uint8 internal constant REENTRANCYLOCK__LOCKED = 2;

    modifier nonReentrant() {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if ($.locked == REENTRANCYLOCK__LOCKED) revert ErrorsLib.Reentrancy();

        $.locked = REENTRANCYLOCK__LOCKED;
        _;
        $.locked = REENTRANCYLOCK__UNLOCKED;
    }

    function _msgSender() internal view virtual returns (address) {
        address sender = msg.sender;
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if (sender == address($.evc)) {
            (sender,) = IEVC($.evc).getCurrentOnBehalfOfAccount(address(0));
        }

        return sender;
    }
}
