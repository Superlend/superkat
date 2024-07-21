// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
import {EulerAggregationVault, IEulerAggregationVault} from "./EulerAggregationVault.sol";
// libs
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title EulerAggregationVaultFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerAggregationVaultFactory {
    error WithdrawalQueueAlreadyWhitelisted();
    error NotWhitelistedWithdrawalQueueImpl();
    error InvalidQuery();

    /// core dependencies
    address public immutable balanceTracker;
    /// core modules implementations addresses
    address public immutable rewardsModule;
    address public immutable hooksModule;
    address public immutable feeModule;
    address public immutable strategyModule;
    address public immutable rebalanceModule;

    address[] public aggregationVaults;

    /// @dev Init params struct.
    struct FactoryParams {
        address owner;
        address balanceTracker;
        address rewardsModuleImpl;
        address hooksModuleImpl;
        address feeModuleImpl;
        address strategyModuleImpl;
        address rebalanceModuleImpl;
    }

    event WhitelistWithdrawalQueueImpl(address withdrawalQueueImpl);
    event DeployEulerAggregationVault(
        address indexed _owner, address _aggregationVault, address indexed _withdrawalQueueImpl, address indexed _asset
    );

    /// @notice Constructor.
    /// @param _factoryParams FactoryParams struct.
    constructor(FactoryParams memory _factoryParams) {
        balanceTracker = _factoryParams.balanceTracker;
        rewardsModule = Clones.clone(_factoryParams.rewardsModuleImpl);
        hooksModule = Clones.clone(_factoryParams.hooksModuleImpl);
        feeModule = Clones.clone(_factoryParams.feeModuleImpl);
        strategyModule = Clones.clone(_factoryParams.strategyModuleImpl);
        rebalanceModule = Clones.clone(_factoryParams.rebalanceModuleImpl);
    }

    /// @notice Deploy a new aggregation vault.
    /// @dev This will clone a new WithdrawalQueue plugin instance for the aggregation vault.
    /// @dev  This will use the defaut Rebalancer plugin configured in this factory.
    /// @dev Both plugins are possible to change by the aggregation vault manager.
    /// @param _asset Aggreation vault' asset address.
    /// @param _name Vaut name.
    /// @param _symbol Vault symbol.
    /// @param _initialCashAllocationPoints The amount of points to initally allocate for cash reserve.
    /// @return eulerAggregationVault The address of the new deployed aggregation vault.
    function deployEulerAggregationVault(
        address _withdrawalQueueImpl,
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external returns (address) {
        // deploy new aggregation vault
        IEulerAggregationVault.ConstructorParams memory aggregationVaultConstructorParams = IEulerAggregationVault
            .ConstructorParams({
            rewardsModule: rewardsModule,
            hooksModule: hooksModule,
            feeModule: feeModule,
            strategyModule: strategyModule,
            rebalanceModule: rebalanceModule
        });
        EulerAggregationVault eulerAggregationVault = new EulerAggregationVault(aggregationVaultConstructorParams);

        IEulerAggregationVault.InitParams memory aggregationVaultInitParams = IEulerAggregationVault.InitParams({
            aggregationVaultOwner: msg.sender,
            asset: _asset,
            withdrawalQueuePlugin: Clones.clone(_withdrawalQueueImpl),
            balanceTracker: balanceTracker,
            name: _name,
            symbol: _symbol,
            initialCashAllocationPoints: _initialCashAllocationPoints
        });
        eulerAggregationVault.init(aggregationVaultInitParams);

        aggregationVaults.push(address(eulerAggregationVault));

        emit DeployEulerAggregationVault(msg.sender, address(eulerAggregationVault), _withdrawalQueueImpl, _asset);

        return address(eulerAggregationVault);
    }

    /// @notice Fetch the length of the deployed aggregation vaults list.
    /// @return The length of the aggregation vaults list array.
    function getAggregationVaultsListLength() external view returns (uint256) {
        return aggregationVaults.length;
    }

    /// @notice Get a slice of the deployed aggregation vaults array.
    /// @param _start Start index of the slice.
    /// @param _end End index of the slice.
    /// @return aggregationVaultsList An array containing the slice of the deployed aggregation vaults list.
    function getAggregationVaultsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = aggregationVaults.length;
        if (_end == type(uint256).max) _end = length;
        if (_end < _start || _end > length) revert InvalidQuery();

        address[] memory aggregationVaultsList = new address[](_end - _start);
        for (uint256 i; i < _end - _start; ++i) {
            aggregationVaultsList[i] = aggregationVaults[_start + i];
        }

        return aggregationVaultsList;
    }
}
