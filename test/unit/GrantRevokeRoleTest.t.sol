// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAccessControl, AccessControlUpgradeable} from "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {YieldAggregatorBase} from "../common/YieldAggregatorBase.t.sol";

contract GrantRevokeRoleTest is YieldAggregatorBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testGrantRoleRevokeRole() public {
        address OWNER2 = makeAddr("OWNER2");
        address OWNER3 = makeAddr("OWNER3");
        bytes32 DEFAULT_ADMIN_ROLE = AccessControlUpgradeable(eulerYieldAggregatorVault).DEFAULT_ADMIN_ROLE();

        vm.prank(OWNER2);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER2, DEFAULT_ADMIN_ROLE)
        );
        eulerYieldAggregatorVault.grantRole(DEFAULT_ADMIN_ROLE, OWNER2);

        vm.prank(OWNER2);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER2, DEFAULT_ADMIN_ROLE)
        );
        eulerYieldAggregatorVault.revokeRole(DEFAULT_ADMIN_ROLE, deployer);

        vm.prank(deployer);
        eulerYieldAggregatorVault.grantRole(DEFAULT_ADMIN_ROLE, OWNER2);
        assertTrue(eulerYieldAggregatorVault.hasRole(DEFAULT_ADMIN_ROLE, OWNER2));

        vm.prank(OWNER2);
        eulerYieldAggregatorVault.grantRole(DEFAULT_ADMIN_ROLE, OWNER3);
        assertTrue(eulerYieldAggregatorVault.hasRole(DEFAULT_ADMIN_ROLE, OWNER3));

        vm.prank(OWNER2);
        eulerYieldAggregatorVault.revokeRole(DEFAULT_ADMIN_ROLE, OWNER3);
        assertFalse(eulerYieldAggregatorVault.hasRole(DEFAULT_ADMIN_ROLE, OWNER3));
    }
}
