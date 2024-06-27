// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IWithdrawalQueue {
    function init(address _owner, address _eulerAggregationVault) external;
    function addStrategyToWithdrawalQueue(address _strategy) external;
    function removeStrategyFromWithdrawalQueue(address _strategy) external;
    function callWithdrawalQueue(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 availableAssets
    ) external;
    function reorderWithdrawalQueue(uint8 _index1, uint8 _index2) external;

    function withdrawalQueueLength() external view returns (uint256);
    function getWithdrawalQueueArray() external view returns (address[] memory, uint256);
}
