// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IEulerEarnFactory {
    function deployEulerEarn(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external returns (address);

    function eulerEarnImpl() external view returns (address);
    function getEulerEarnVaultsListLength() external view returns (uint256);
    function getEulerEarnVaultsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory);
    function isValidDeployment(address _earnVaultAddress) external view returns (bool);
}
