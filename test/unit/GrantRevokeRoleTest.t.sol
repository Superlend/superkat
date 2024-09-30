// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAccessControl, AccessControlUpgradeable} from "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {EulerEarnBase} from "../common/EulerEarnBase.t.sol";

contract GrantRevokeRoleTest is EulerEarnBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testGrantRoleRevokeRole() public {
        address OWNER2 = makeAddr("OWNER2");
        address OWNER3 = makeAddr("OWNER3");
        bytes32 DEFAULT_ADMIN_ROLE = AccessControlUpgradeable(eulerEulerEarnVault).DEFAULT_ADMIN_ROLE();

        vm.prank(OWNER2);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER2, DEFAULT_ADMIN_ROLE)
        );
        eulerEulerEarnVault.grantRole(DEFAULT_ADMIN_ROLE, OWNER2);

        vm.prank(OWNER2);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER2, DEFAULT_ADMIN_ROLE)
        );
        eulerEulerEarnVault.revokeRole(DEFAULT_ADMIN_ROLE, deployer);

        vm.prank(deployer);
        eulerEulerEarnVault.grantRole(DEFAULT_ADMIN_ROLE, OWNER2);
        assertTrue(eulerEulerEarnVault.hasRole(DEFAULT_ADMIN_ROLE, OWNER2));

        vm.prank(OWNER2);
        eulerEulerEarnVault.grantRole(DEFAULT_ADMIN_ROLE, OWNER3);
        assertTrue(eulerEulerEarnVault.hasRole(DEFAULT_ADMIN_ROLE, OWNER3));

        vm.prank(OWNER2);
        eulerEulerEarnVault.revokeRole(DEFAULT_ADMIN_ROLE, OWNER3);
        assertFalse(eulerEulerEarnVault.hasRole(DEFAULT_ADMIN_ROLE, OWNER3));
    }
}
