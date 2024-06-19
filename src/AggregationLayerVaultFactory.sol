// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
import {Rewards} from "./module/Rewards.sol";
import {Hooks} from "./module/Hooks.sol";
import {Fee} from "./module/Fee.sol";
import {WithdrawalQueue} from "./plugin/WithdrawalQueue.sol";
import {AggregationLayerVault} from "./AggregationLayerVault.sol";
// libs
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract AggregationLayerVaultFactory {
    /// core dependencies
    address public immutable evc;
    address public immutable balanceTracker;
    /// core modules implementations addresses
    address public immutable rewardsModuleImpl;
    address public immutable hooksModuleImpl;
    address public immutable feeModuleImpl;
    address public immutable allocationPointsModuleImpl;
    /// plugins
    /// @dev Rebalancer plugin contract address, one instance can serve different aggregation vaults
    address public immutable rebalancer;
    /// @dev WithdrawalQueue plugin implementation address, need to be deployed per aggregation vault
    address public immutable withdrawalQueueImpl;

    struct FactoryParams {
        address evc;
        address balanceTracker;
        address rewardsModuleImpl;
        address hooksModuleImpl;
        address feeModuleImpl;
        address allocationPointsModuleImpl;
        address rebalancer;
        address withdrawalQueueImpl;
    }

    constructor(FactoryParams memory _factoryParams) {
        evc = _factoryParams.evc;
        balanceTracker = _factoryParams.balanceTracker;
        rewardsModuleImpl = _factoryParams.rewardsModuleImpl;
        hooksModuleImpl = _factoryParams.hooksModuleImpl;
        feeModuleImpl = _factoryParams.feeModuleImpl;
        allocationPointsModuleImpl = _factoryParams.allocationPointsModuleImpl;

        rebalancer = _factoryParams.rebalancer;
        withdrawalQueueImpl = _factoryParams.withdrawalQueueImpl;
    }

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
        address allocationpointsModuleAddr = Clones.clone(allocationPointsModuleImpl);

        // cloning plugins
        WithdrawalQueue withdrawalQueue = WithdrawalQueue(Clones.clone(withdrawalQueueImpl));

        // deploy new aggregation vault
        AggregationLayerVault aggregationLayerVault =
            new AggregationLayerVault(rewardsModuleAddr, hooksModuleAddr, feeModuleAddr, allocationpointsModuleAddr);

        AggregationLayerVault.InitParams memory aggregationVaultInitParams = AggregationLayerVault.InitParams({
            evc: evc,
            balanceTracker: balanceTracker,
            withdrawalQueuePeriphery: address(withdrawalQueue),
            rebalancerPerihpery: rebalancer,
            aggregationVaultOwner: msg.sender,
            asset: _asset,
            name: _name,
            symbol: _symbol,
            initialCashAllocationPoints: _initialCashAllocationPoints
        });

        withdrawalQueue.init(msg.sender, address(aggregationLayerVault));
        aggregationLayerVault.init(aggregationVaultInitParams);

        return address(aggregationLayerVault);
    }
}
