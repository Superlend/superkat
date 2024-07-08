// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
import {Rewards} from "./module/Rewards.sol";
import {Hooks} from "./module/Hooks.sol";
import {Fee} from "./module/Fee.sol";
import {WithdrawalQueue} from "../plugin/WithdrawalQueue.sol";
import {EulerAggregationVault, IEulerAggregationVault} from "./EulerAggregationVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// libs
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title EulerAggregationVaultFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerAggregationVaultFactory is Ownable {
    error WithdrawalQueueAlreadyWhitelisted();
    error NotWhitelistedWithdrawalQueueImpl();

    /// core dependencies
    address public immutable balanceTracker;
    /// core modules implementations addresses
    address public immutable rewardsModuleImpl;
    address public immutable hooksModuleImpl;
    address public immutable feeModuleImpl;
    address public immutable allocationPointsModuleImpl;
    /// plugins
    /// @dev Rebalancer plugin contract address, one instance can serve different aggregation vaults
    address public immutable rebalancer;
    /// @dev Mapping to set whitelisted WhithdrawalQueue plugin implementation.
    mapping(address => bool) public isWhitelistedWithdrawalQueueImpl;
    /// @dev An array of the whitelisted WithdrawalQueue plugin implementations.
    address[] public withdrawalQueueImpls;

    /// @dev Init params struct.
    struct FactoryParams {
        address balanceTracker;
        address rewardsModuleImpl;
        address hooksModuleImpl;
        address feeModuleImpl;
        address allocationPointsModuleImpl;
        address rebalancer;
    }

    /// @notice Constructor.
    /// @param _owner Factory owner.
    /// @param _factoryParams FactoryParams struct.
    constructor(address _owner, FactoryParams memory _factoryParams) Ownable(_owner) {
        balanceTracker = _factoryParams.balanceTracker;
        rewardsModuleImpl = _factoryParams.rewardsModuleImpl;
        hooksModuleImpl = _factoryParams.hooksModuleImpl;
        feeModuleImpl = _factoryParams.feeModuleImpl;
        allocationPointsModuleImpl = _factoryParams.allocationPointsModuleImpl;

        rebalancer = _factoryParams.rebalancer;
    }

    function whitelistWithdrawalQueueImpl(address _withdrawalQueuImpl) external onlyOwner {
        if (isWhitelistedWithdrawalQueueImpl[_withdrawalQueuImpl]) revert WithdrawalQueueAlreadyWhitelisted();

        isWhitelistedWithdrawalQueueImpl[_withdrawalQueuImpl] = true;

        withdrawalQueueImpls.push(_withdrawalQueuImpl);
    }

    /// @notice Deploy a new aggregation layer vault.
    /// @dev This will clone a new WithdrawalQueue plugin instance for the aggregation layer vault.
    /// @dev  This will use the defaut Rebalancer plugin configured in this factory.
    /// @dev Both plugins are possible to change by the aggregation layer vault manager.
    /// @param _asset Aggreation layer vault' asset address.
    /// @param _name Vaut name.
    /// @param _symbol Vault symbol.
    /// @param _initialCashAllocationPoints The amount of points to initally allocate for cash reserve.
    /// @return eulerAggregationVault The address of the new deployed aggregation layer vault.
    function deployEulerAggregationVault(
        address _withdrawalQueueImpl,
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external returns (address) {
        if (!isWhitelistedWithdrawalQueueImpl[_withdrawalQueueImpl]) revert NotWhitelistedWithdrawalQueueImpl();

        // cloning core modules
        address rewardsModuleAddr = Clones.clone(rewardsModuleImpl);
        address hooksModuleAddr = Clones.clone(hooksModuleImpl);
        address feeModuleAddr = Clones.clone(feeModuleImpl);
        address allocationpointsModuleAddr = Clones.clone(allocationPointsModuleImpl);

        // cloning plugins
        WithdrawalQueue withdrawalQueue = WithdrawalQueue(Clones.clone(_withdrawalQueueImpl));

        // deploy new aggregation vault
        EulerAggregationVault eulerAggregationVault =
            new EulerAggregationVault(rewardsModuleAddr, hooksModuleAddr, feeModuleAddr, allocationpointsModuleAddr);

        IEulerAggregationVault.InitParams memory aggregationVaultInitParams = IEulerAggregationVault.InitParams({
            balanceTracker: balanceTracker,
            withdrawalQueuePlugin: address(withdrawalQueue),
            rebalancerPlugin: rebalancer,
            aggregationVaultOwner: msg.sender,
            asset: _asset,
            name: _name,
            symbol: _symbol,
            initialCashAllocationPoints: _initialCashAllocationPoints
        });

        withdrawalQueue.init(msg.sender, address(eulerAggregationVault));
        eulerAggregationVault.init(aggregationVaultInitParams);

        return address(eulerAggregationVault);
    }
}
