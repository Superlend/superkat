// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EVaultTestBase, TestERC20} from "evk/test/unit/evault/EVaultTestBase.t.sol";
import {FourSixTwoSixAgg} from "../../src/FourSixTwoSixAgg.sol";

contract FourSixTwoSixAggBase is EVaultTestBase {
    address deployer;
    address user1;
    address user2;

    FourSixTwoSixAgg fourSixTwoSixAgg;

    function setUp() public virtual override {
        super.setUp();

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");

        vm.prank(deployer);
        fourSixTwoSixAgg = new FourSixTwoSixAgg(
            evc,
            address(assetTST),
            "assetTST_Agg",
            "assetTST_Agg",
            type(uint120).max,
            new address[](0),
            new uint256[](0)
        );
    }
}
