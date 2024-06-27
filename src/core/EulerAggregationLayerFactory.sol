// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
import {Rewards} from "./module/Rewards.sol";
import {Hooks} from "./module/Hooks.sol";
import {Fee} from "./module/Fee.sol";
import {WithdrawalQueue} from "../plugin/WithdrawalQueue.sol";
import {EulerAggregationLayer, IEulerAggregationLayer} from "./EulerAggregationLayer.sol";
// libs
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title EulerAggregationLayerFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerAggregationLayerFactory {
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

    /// @dev Init params struct.
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

    /// @notice Constructor.
    /// @param _factoryParams FactoryParams struct.
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

    /// @notice Deploy a new aggregation layer vault.
    /// @dev This will clone a new WithdrawalQueue plugin instance for the aggregation layer vault.
    /// @dev  This will use the defaut Rebalancer plugin configured in this factory.
    /// @dev Both plugins are possible to change by the aggregation layer vault manager.
    /// @param _asset Aggreation layer vault' asset address.
    /// @param _name Vaut name.
    /// @param _symbol Vault symbol.
    /// @param _initialCashAllocationPoints The amount of points to initally allocate for cash reserve.
    /// @return eulerAggregationLayer The address of the new deployed aggregation layer vault.
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
        EulerAggregationLayer eulerAggregationLayer =
            new EulerAggregationLayer(rewardsModuleAddr, hooksModuleAddr, feeModuleAddr, allocationpointsModuleAddr);

        IEulerAggregationLayer.InitParams memory aggregationVaultInitParams = IEulerAggregationLayer.InitParams({
            evc: evc,
            balanceTracker: balanceTracker,
            withdrawalQueuePlugin: address(withdrawalQueue),
            rebalancerPlugin: rebalancer,
            aggregationVaultOwner: msg.sender,
            asset: _asset,
            name: _name,
            symbol: _symbol,
            initialCashAllocationPoints: _initialCashAllocationPoints
        });

        withdrawalQueue.init(msg.sender, address(eulerAggregationLayer));
        eulerAggregationLayer.init(aggregationVaultInitParams);

        return address(eulerAggregationLayer);
    }
}
