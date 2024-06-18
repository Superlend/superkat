// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
// core modules
import {Rewards} from "./modules/Rewards.sol";
import {Hooks} from "./modules/Hooks.sol";
import {Fee} from "./modules/Fee.sol";
// core peripheries
import {WithdrawalQueue} from "./WithdrawalQueue.sol";
import {FourSixTwoSixAgg} from "./FourSixTwoSixAgg.sol";

contract FourSixTwoSixAggFactory {
    /// core dependencies
    address public immutable evc;
    address public immutable balanceTracker;
    /// core modules
    address public immutable rewardsModuleImpl;
    address public immutable hooksModuleImpl;
    address public immutable feeModuleImpl;
    address public immutable allocationpointsModuleImpl;
    /// peripheries
    /// @dev Rebalancer periphery, one instance can serve different aggregation vaults
    address public immutable rebalancerAddr;
    /// @dev Withdrawal queue perihperhy, need to be deployed per aggregation vault
    address public immutable withdrawalQueueAddr;

    constructor(
        address _evc,
        address _balanceTracker,
        address _rewardsModuleImpl,
        address _hooksModuleImpl,
        address _feeModuleImpl,
        address _allocationpointsModuleImpl,
        address _rebalancerAddr,
        address _withdrawalQueueAddr
    ) {
        evc = _evc;
        balanceTracker = _balanceTracker;
        rewardsModuleImpl = _rewardsModuleImpl;
        hooksModuleImpl = _hooksModuleImpl;
        feeModuleImpl = _feeModuleImpl;
        allocationpointsModuleImpl = _allocationpointsModuleImpl;

        rebalancerAddr = _rebalancerAddr;
        withdrawalQueueAddr = _withdrawalQueueAddr;
    }

    // TODO: decrease bytecode size, use clones or something
    function deployEulerAggregationLayer(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external returns (address) {
        // cloning core modules
        address rewardsModuleAddr = Clones.clone(rewardsModuleImpl);
        address hooksModuleAddr = Clones.clone(hooksModuleImpl);
        address feeModuleAddr = Clones.clone(feeModuleImpl);
        address allocationpointsModuleAddr = Clones.clone(allocationpointsModuleImpl);

        // cloning peripheries
        WithdrawalQueue withdrawalQueue = WithdrawalQueue(Clones.clone(withdrawalQueueAddr));

        // deploy new aggregation vault
        FourSixTwoSixAgg fourSixTwoSixAgg =
            new FourSixTwoSixAgg(rewardsModuleAddr, hooksModuleAddr, feeModuleAddr, allocationpointsModuleAddr);

        FourSixTwoSixAgg.InitParams memory aggregationVaultInitParams = FourSixTwoSixAgg.InitParams({
            evc: evc,
            balanceTracker: balanceTracker,
            withdrawalQueuePeriphery: address(withdrawalQueue),
            rebalancerPerihpery: rebalancerAddr,
            aggregationVaultOwner: msg.sender,
            asset: _asset,
            name: _name,
            symbol: _symbol,
            initialCashAllocationPoints: _initialCashAllocationPoints
        });

        withdrawalQueue.init(msg.sender, address(fourSixTwoSixAgg));
        fourSixTwoSixAgg.init(aggregationVaultInitParams);

        return address(fourSixTwoSixAgg);
    }
}
