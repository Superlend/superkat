// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {FourSixTwoSixAgg} from "../../src/FourSixTwoSixAgg.sol";

contract FourSixTwoSixAggBase is EVaultTestBase {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address deployer;
    address user1;
    address user2;
    address manager;

    FourSixTwoSixAgg fourSixTwoSixAgg;

    function setUp() public virtual override {
        super.setUp();

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");

        vm.startPrank(deployer);
        fourSixTwoSixAgg = new FourSixTwoSixAgg(
            evc,
            address(0),
            address(assetTST),
            "assetTST_Agg",
            "assetTST_Agg",
            CASH_RESERVE_ALLOCATION_POINTS,
            new address[](0),
            new uint256[](0)
        );

        // grant admin roles to deployer
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.TREASURY_MANAGER_ROLE_ADMIN_ROLE(), deployer);

        // grant roles to manager
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.TREASURY_MANAGER_ROLE(), manager);

        vm.stopPrank();
    }

    function testInitialParams() public {
        FourSixTwoSixAgg.Strategy memory cashReserve = fourSixTwoSixAgg.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.active, true);

        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE()),
            fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE()
        );
        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE()),
            fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE()
        );
        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE()),
            fourSixTwoSixAgg.STRATEGY_ADDER_ROLE_ADMIN_ROLE()
        );
        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE()),
            fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE_ADMIN_ROLE()
        );
        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.TREASURY_MANAGER_ROLE()),
            fourSixTwoSixAgg.TREASURY_MANAGER_ROLE_ADMIN_ROLE()
        );

        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE_ADMIN_ROLE(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE_ADMIN_ROLE(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.TREASURY_MANAGER_ROLE_ADMIN_ROLE(), deployer));

        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.TREASURY_MANAGER_ROLE(), manager));
    }

    function _addStrategy(address from, address strategy, uint256 allocationPoints) internal {
        vm.prank(from);
        fourSixTwoSixAgg.addStrategy(strategy, allocationPoints);
    }

    function _getWithdrawalQueue() internal view returns (address[] memory) {
        uint256 length = fourSixTwoSixAgg.withdrawalQueueLength();

        address[] memory queue = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            queue[i] = fourSixTwoSixAgg.withdrawalQueue(i);
        }
        return queue;
    }
}
