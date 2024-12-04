// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract SkimTest is EulerEarnBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testSkimWhenAssetIsUnderlying() public {
        address asset = eulerEulerEarnVault.asset();

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.CanNotSkim.selector);
        eulerEulerEarnVault.skim(asset, manager);
        vm.stopPrank();
    }

    function testSkimWhenCallerIsRandom() public {
        address asset = eulerEulerEarnVault.asset();

        vm.startPrank(user1);
        vm.expectRevert();
        eulerEulerEarnVault.skim(asset, manager);
        vm.stopPrank();
    }

    function testSkimWhenAssetIsStrategy() public {
        uint256 allocationPoints = 500e18;
        _addStrategy(manager, address(eTST), allocationPoints);

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.CanNotSkim.selector);
        eulerEulerEarnVault.skim(address(eTST), manager);
        vm.stopPrank();
    }

    function testSkim() public {
        assetTST2.mint(user1, 10e18);
        vm.prank(user1);
        assetTST2.transfer(address(eulerEulerEarnVault), 10e18);

        uint256 managerBalanceBefore = assetTST2.balanceOf(manager);

        vm.prank(manager);
        eulerEulerEarnVault.skim(address(assetTST2), manager);

        assertEq(assetTST2.balanceOf(manager) - managerBalanceBefore, 10e18);
    }
}
