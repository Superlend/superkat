// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
import {YieldAggregator, IYieldAggregator} from "./YieldAggregator.sol";
// libs
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title YieldAggregatorFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract YieldAggregatorFactory {
    error InvalidQuery();

    /// core dependencies
    address public immutable evc;
    address public immutable balanceTracker;
    /// core modules implementations addresses
    address public immutable yieldAggregatorVaultModule;
    address public immutable rewardsModule;
    address public immutable hooksModule;
    address public immutable feeModule;
    address public immutable strategyModule;
    address public immutable rebalanceModule;
    address public immutable withdrawalQueueModule;
    /// yield aggregator implementation address
    address public immutable yieldAggregatorImpl;

    address[] public yieldAggregatorVaults;

    /// @dev Init params struct.
    struct FactoryParams {
        address owner;
        address evc;
        address balanceTracker;
        address yieldAggregatorVaultModule;
        address rewardsModule;
        address hooksModule;
        address feeModule;
        address strategyModule;
        address rebalanceModule;
        address withdrawalQueueModule;
    }

    event DeployYieldAggregator(address indexed _owner, address _yieldAggregatorVault, address indexed _asset);

    /// @dev Constructor.
    /// @param _factoryParams FactoryParams struct.
    constructor(FactoryParams memory _factoryParams) {
        evc = _factoryParams.evc;
        balanceTracker = _factoryParams.balanceTracker;
        yieldAggregatorVaultModule = _factoryParams.yieldAggregatorVaultModule;
        rewardsModule = _factoryParams.rewardsModule;
        hooksModule = _factoryParams.hooksModule;
        feeModule = _factoryParams.feeModule;
        strategyModule = _factoryParams.strategyModule;
        rebalanceModule = _factoryParams.rebalanceModule;
        withdrawalQueueModule = _factoryParams.withdrawalQueueModule;

        IYieldAggregator.ConstructorParams memory yieldAggregatorVaultConstructorParams = IYieldAggregator
            .ConstructorParams({
            evc: evc,
            yieldAggregatorVaultModule: yieldAggregatorVaultModule,
            rewardsModule: rewardsModule,
            hooksModule: hooksModule,
            feeModule: feeModule,
            strategyModule: strategyModule,
            rebalanceModule: rebalanceModule,
            withdrawalQueueModule: withdrawalQueueModule
        });
        yieldAggregatorImpl = address(new YieldAggregator(yieldAggregatorVaultConstructorParams));
    }

    /// @notice Deploy a new yield aggregator vault.
    /// @param _asset Aggreation vault' asset address.
    /// @param _name Vaut name.
    /// @param _symbol Vault symbol.
    /// @param _initialCashAllocationPoints The amount of points to initally allocate for cash reserve.
    /// @return The address of the new deployed yield aggregator.
    function deployYieldAggregator(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external returns (address) {
        address eulerYieldAggregatorVault = Clones.clone(yieldAggregatorImpl);

        IYieldAggregator.InitParams memory yieldAggregatorVaultInitParams = IYieldAggregator.InitParams({
            yieldAggregatorVaultOwner: msg.sender,
            asset: _asset,
            balanceTracker: balanceTracker,
            name: _name,
            symbol: _symbol,
            initialCashAllocationPoints: _initialCashAllocationPoints
        });
        IYieldAggregator(eulerYieldAggregatorVault).init(yieldAggregatorVaultInitParams);

        yieldAggregatorVaults.push(address(eulerYieldAggregatorVault));

        emit DeployYieldAggregator(msg.sender, address(eulerYieldAggregatorVault), _asset);

        return eulerYieldAggregatorVault;
    }

    /// @notice Fetch the length of the deployed yield aggregator vaults list.
    /// @return The length of the yield aggregator vaults list array.
    function getYieldAggregatorVaultsListLength() external view returns (uint256) {
        return yieldAggregatorVaults.length;
    }

    /// @notice Get a slice of the deployed yield aggregator vaults array.
    /// @param _start Start index of the slice.
    /// @param _end End index of the slice.
    /// @return An array containing the slice of the deployed yield aggregator vaults list.
    function getYieldAggregatorVaultsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = yieldAggregatorVaults.length;
        if (_end == type(uint256).max) _end = length;
        if (_end < _start || _end > length) revert InvalidQuery();

        address[] memory yieldAggregatorVaultsList = new address[](_end - _start);
        for (uint256 i; i < _end - _start; ++i) {
            yieldAggregatorVaultsList[i] = yieldAggregatorVaults[_start + i];
        }

        return yieldAggregatorVaultsList;
    }
}
