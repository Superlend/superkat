// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {YieldAggregatorBase, YieldAggregator, ErrorsLib} from "../common/YieldAggregatorBase.t.sol";

contract DepositWithdrawMintBurnFuzzTest is YieldAggregatorBase {
    uint256 constant MAX_ALLOWED = type(uint208).max;

    function setUp() public virtual override {
        super.setUp();
    }

    function testFuzzDeposit(uint256 _assets) public {
        _assets = bound(_assets, 0, MAX_ALLOWED);

        // moch the scenario of _assets ownership
        assetTST.mint(user1, _assets);

        uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        _deposit(user1, _assets);

        assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore + _assets);
        assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore + _assets);
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore + _assets);
        assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - _assets);
    }

    function testFuzzWithdraw(
        address _receiver,
        uint256 _assetsToDeposit,
        uint256 _assetsToWithdraw,
        uint256 _timestampAfterDeposit
    ) public {
        vm.assume(_receiver != address(0));

        _assetsToDeposit = bound(_assetsToDeposit, 1, MAX_ALLOWED - 1);
        _assetsToWithdraw = bound(_assetsToWithdraw, 0, _assetsToDeposit);
        _timestampAfterDeposit = bound(_timestampAfterDeposit, 0, 86400);

        // deposit
        assetTST.mint(user1, _assetsToDeposit);
        _deposit(user1, _assetsToDeposit);
        vm.warp(block.timestamp + _timestampAfterDeposit);

        // test revert scenario
        uint256 assets = eulerYieldAggregatorVault.previewRedeem(eulerYieldAggregatorVault.balanceOf(user1));
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(ErrorsLib.ERC4626ExceededMaxWithdraw.selector, user1, assets + 1, assets)
        );
        eulerYieldAggregatorVault.withdraw(assets + 1, user1, user1);
        vm.stopPrank();

        // fuzz partial & full withdraws
        uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 receiverAssetBalanceBefore = assetTST.balanceOf(_receiver);

        vm.startPrank(user1);
        eulerYieldAggregatorVault.withdraw(_assetsToWithdraw, _receiver, user1);
        vm.stopPrank();

        assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore - _assetsToWithdraw);
        assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore - _assetsToWithdraw);
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - _assetsToWithdraw);
        assertEq(assetTST.balanceOf(_receiver), receiverAssetBalanceBefore + _assetsToWithdraw);
    }

    function testFuzzMint(uint256 _shares) public {
        // mock the scenario of _assets ownership
        uint256 assets = eulerYieldAggregatorVault.previewMint(_shares);
        if (assets > MAX_ALLOWED) assets = MAX_ALLOWED;
        assetTST.mint(user1, assets);
        _shares = eulerYieldAggregatorVault.previewDeposit(assets);

        uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        _mint(user1, assets, _shares);

        assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore + _shares);
        assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore + _shares);
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore + assets);
        assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - assets);
    }

    function testFuzzRedeem(address _receiver, uint256 _sharesToMint, uint256 _sharesToRedeem) public {
        vm.assume(_receiver != address(0));

        _sharesToMint = bound(_sharesToMint, 1, type(uint256).max - 1);

        // deposit
        uint256 assetsToDeposit = eulerYieldAggregatorVault.previewMint(_sharesToMint);
        if (assetsToDeposit > MAX_ALLOWED) assetsToDeposit = MAX_ALLOWED;
        assetTST.mint(user1, assetsToDeposit);

        _sharesToMint = eulerYieldAggregatorVault.previewDeposit(assetsToDeposit);
        _sharesToRedeem = bound(_sharesToRedeem, 0, _sharesToMint);
        _mint(user1, assetsToDeposit, _sharesToMint);
        vm.warp(block.timestamp + 86400);

        // test revert scenario
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(ErrorsLib.ERC4626ExceededMaxRedeem.selector, user1, _sharesToMint + 1, _sharesToMint)
        );
        eulerYieldAggregatorVault.redeem(_sharesToMint + 1, user1, user1);
        vm.stopPrank();

        // fuzz partial & full redeem
        uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 receiverAssetBalanceBefore = assetTST.balanceOf(_receiver);

        vm.startPrank(user1);
        uint256 assetsToWithdraw = eulerYieldAggregatorVault.redeem(_sharesToRedeem, _receiver, user1);
        vm.stopPrank();

        assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore - _sharesToRedeem);
        assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore - _sharesToRedeem);
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - assetsToWithdraw);
        assertEq(assetTST.balanceOf(_receiver), receiverAssetBalanceBefore + assetsToWithdraw);
    }

    function _deposit(address _from, uint256 _assets) private {
        vm.startPrank(_from);
        assetTST.approve(address(eulerYieldAggregatorVault), _assets);
        eulerYieldAggregatorVault.deposit(_assets, _from);
        vm.stopPrank();
    }

    function _mint(address _from, uint256 _assets, uint256 _shares) private {
        vm.startPrank(_from);
        assetTST.approve(address(eulerYieldAggregatorVault), _assets);
        eulerYieldAggregatorVault.mint(_shares, _from);
        vm.stopPrank();
    }
}
