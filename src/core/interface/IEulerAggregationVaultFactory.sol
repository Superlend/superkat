// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IEulerAggregationVaultFactory {
    function isWhitelistedWithdrawalQueueImpl(address _withdrawalQueueImpl) external view returns (bool);
}
