// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {FourSixTwoSixAgg} from "../../src/FourSixTwoSixAgg.sol";
import {Rebalancer} from "../../src/Rebalancer.sol";
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
import {Hooks} from "../../src/Hooks.sol";

contract FourSixTwoSixAggBase is EVaultTestBase {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address deployer;
    address user1;
    address user2;
    address manager;

    FourSixTwoSixAgg fourSixTwoSixAgg;
    Rebalancer rebalancer;

    function setUp() public virtual override {
        super.setUp();

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");

        vm.startPrank(deployer);
        rebalancer = new Rebalancer();
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
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_MANAGER_ADMIN(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER_ADMIN(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ADMIN(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.MANAGER_ADMIN(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.REBALANCER_ADMIN(), deployer);

        // grant roles to manager
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_MANAGER(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_MANAGER(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.MANAGER(), manager);

        // grant rebalancing role
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.REBALANCER(), address(rebalancer));

        vm.stopPrank();
    }

    function testInitialParams() public {
        FourSixTwoSixAgg.Strategy memory cashReserve = fourSixTwoSixAgg.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.active, true);

        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.STRATEGY_MANAGER()),
            fourSixTwoSixAgg.STRATEGY_MANAGER_ADMIN()
        );
        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.WITHDRAW_QUEUE_MANAGER()),
            fourSixTwoSixAgg.WITHDRAW_QUEUE_MANAGER_ADMIN()
        );
        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.STRATEGY_ADDER()), fourSixTwoSixAgg.STRATEGY_ADDER_ADMIN()
        );
        assertEq(
            fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.STRATEGY_REMOVER()),
            fourSixTwoSixAgg.STRATEGY_REMOVER_ADMIN()
        );
        assertEq(fourSixTwoSixAgg.getRoleAdmin(fourSixTwoSixAgg.MANAGER()), fourSixTwoSixAgg.MANAGER_ADMIN());

        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_MANAGER_ADMIN(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_ADDER_ADMIN(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ADMIN(), deployer));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.MANAGER_ADMIN(), deployer));

        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_MANAGER(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_MANAGER(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_ADDER(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.STRATEGY_REMOVER(), manager));
        assertTrue(fourSixTwoSixAgg.hasRole(fourSixTwoSixAgg.MANAGER(), manager));
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
