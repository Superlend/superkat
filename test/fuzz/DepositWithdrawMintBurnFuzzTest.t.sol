// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {console2, FourSixTwoSixAggBase, FourSixTwoSixAgg} from "../common/FourSixTwoSixAggBase.t.sol";

contract DepositWithdrawMintBurnFuzzTest is FourSixTwoSixAggBase {
    uint256 constant MAX_ALLOWED = type(uint256).max;

    function setUp() public virtual override {
        super.setUp();
    }

    function testFuzzDeposit(uint256 _assets) public {
        // moch the scenario of _assets ownership
        assetTST.mint(user1, _assets);

        uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
        uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
        uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        _deposit(user1, _assets);

        assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + _assets);
        assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + _assets);
        assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + _assets);
        assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - _assets);
    }

    function testFuzzWithdraw(
        address _receiver,
        uint256 _assetsToDeposit,
        uint256 _assetsToWithdraw,
        uint256 _timestampAfterDeposit
    ) public {
        vm.assume(_receiver != address(0));

        _assetsToDeposit = bound(_assetsToDeposit, 1, type(uint256).max - 1);
        _assetsToWithdraw = bound(_assetsToWithdraw, 0, _assetsToDeposit);
        _timestampAfterDeposit = bound(_timestampAfterDeposit, 0, 86400);

        // deposit
        assetTST.mint(user1, _assetsToDeposit);
        _deposit(user1, _assetsToDeposit);
        vm.warp(block.timestamp + _timestampAfterDeposit);

        // fuzz partial & full withdraws
        uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
        uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
        uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
        uint256 receiverAssetBalanceBefore = assetTST.balanceOf(_receiver);

        vm.startPrank(user1);
        fourSixTwoSixAgg.withdraw(_assetsToWithdraw, _receiver, user1);
        vm.stopPrank();

        assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore - _assetsToWithdraw);
        assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore - _assetsToWithdraw);
        assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - _assetsToWithdraw);
        assertEq(assetTST.balanceOf(_receiver), receiverAssetBalanceBefore + _assetsToWithdraw);
    }

    function testFuzzMint(uint256 _shares) public {
        // moch the scenario of _assets ownership
        uint256 assets = fourSixTwoSixAgg.previewMint(_shares);
        assetTST.mint(user1, assets);

        uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
        uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
        uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        _mint(user1, assets, _shares);

        assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + _shares);
        assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + _shares);
        assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + assets);
        assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - assets);
    }

    function testFuzzRedeem(
        address _receiver,
        uint256 _sharesToMint,
        uint256 _sharesToRedeem,
        uint256 _timestampAfterDeposit
    ) public {
        vm.assume(_receiver != address(0));

        _sharesToMint = bound(_sharesToMint, 1, type(uint256).max - 1);
        _sharesToRedeem = bound(_sharesToRedeem, 0, _sharesToMint);
        _timestampAfterDeposit = bound(_timestampAfterDeposit, 0, 86400);

        // deposit
        uint256 assetsToDeposit = fourSixTwoSixAgg.previewMint(_sharesToMint);
        assetTST.mint(user1, assetsToDeposit);
        _mint(user1, assetsToDeposit, _sharesToMint);
        vm.warp(block.timestamp + _timestampAfterDeposit);

        // fuzz partial & full redeem
        uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
        uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
        uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
        uint256 receiverAssetBalanceBefore = assetTST.balanceOf(_receiver);

        vm.startPrank(user1);
        uint256 assetsToWithdraw = fourSixTwoSixAgg.redeem(_sharesToRedeem, _receiver, user1);
        vm.stopPrank();

        assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore - _sharesToRedeem);
        assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore - _sharesToRedeem);
        assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - assetsToWithdraw);
        assertEq(assetTST.balanceOf(_receiver), receiverAssetBalanceBefore + assetsToWithdraw);
    }

    function _deposit(address _from, uint256 _assets) private {
        vm.startPrank(_from);
        assetTST.approve(address(fourSixTwoSixAgg), _assets);
        fourSixTwoSixAgg.deposit(_assets, _from);
        vm.stopPrank();
    }

    function _mint(address _from, uint256 _assets, uint256 _shares) private {
        vm.startPrank(_from);
        assetTST.approve(address(fourSixTwoSixAgg), _assets);
        fourSixTwoSixAgg.mint(_shares, _from);
        vm.stopPrank();
    }
}
