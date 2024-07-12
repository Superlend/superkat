// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// contracts
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
    error InvalidQuery();

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
    /// @dev Array to store the addresses of all deployed aggregation vaults.
    address[] public aggregationVaults;

    /// @dev Init params struct.
    struct FactoryParams {
        address owner;
        address balanceTracker;
        address rewardsModuleImpl;
        address hooksModuleImpl;
        address feeModuleImpl;
        address allocationPointsModuleImpl;
        address rebalancer;
    }

    event WhitelistWithdrawalQueueImpl(address withdrawalQueueImpl);
    event DeployEulerAggregationVault(
        address indexed _owner, address _aggregationVault, address indexed _withdrawalQueueImpl, address indexed _asset
    );

    /// @notice Constructor.
    /// @param _factoryParams FactoryParams struct.
    constructor(FactoryParams memory _factoryParams) Ownable(_factoryParams.owner) {
        balanceTracker = _factoryParams.balanceTracker;
        rewardsModuleImpl = _factoryParams.rewardsModuleImpl;
        hooksModuleImpl = _factoryParams.hooksModuleImpl;
        feeModuleImpl = _factoryParams.feeModuleImpl;
        allocationPointsModuleImpl = _factoryParams.allocationPointsModuleImpl;
        rebalancer = _factoryParams.rebalancer;
    }

    /// @notice Whitelist a new WithdrawalQueue implementation.
    /// @dev Can only be called by factory owner.
    /// @param _withdrawalQueuImpl WithdrawalQueue plugin implementation.
    function whitelistWithdrawalQueueImpl(address _withdrawalQueuImpl) external onlyOwner {
        if (isWhitelistedWithdrawalQueueImpl[_withdrawalQueuImpl]) revert WithdrawalQueueAlreadyWhitelisted();

        isWhitelistedWithdrawalQueueImpl[_withdrawalQueuImpl] = true;

        withdrawalQueueImpls.push(_withdrawalQueuImpl);

        emit WhitelistWithdrawalQueueImpl(_withdrawalQueuImpl);
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
        if (!isWhitelistedWithdrawalQueueImpl[_withdrawalQueueImpl]) revert NotWhitelistedWithdrawalQueueImpl();

        // deploy new aggregation vault
        IEulerAggregationVault.ConstructorParams memory aggregationVaultConstructorParams = IEulerAggregationVault
            .ConstructorParams({
            rewardsModule: Clones.clone(rewardsModuleImpl),
            hooksModule: Clones.clone(hooksModuleImpl),
            feeModule: Clones.clone(feeModuleImpl),
            allocationPointsModule: Clones.clone(allocationPointsModuleImpl)
        });
        EulerAggregationVault eulerAggregationVault = new EulerAggregationVault(aggregationVaultConstructorParams);

        IEulerAggregationVault.InitParams memory aggregationVaultInitParams = IEulerAggregationVault.InitParams({
            aggregationVaultOwner: msg.sender,
            asset: _asset,
            withdrawalQueuePlugin: Clones.clone(_withdrawalQueueImpl),
            rebalancerPlugin: rebalancer,
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

    /// @notice Fetch the length of the whitelisted WithdrawalQueue implementations list
    /// @return The length of the proxy list array
    function getWithdrawalQueueImplsListLength() external view returns (uint256) {
        return withdrawalQueueImpls.length;
    }

    /// @notice Return the WithdrawalQueue implementations list.
    /// @return withdrawalQueueImplsList An array of addresses.
    function getWithdrawalQueueImplsList() external view returns (address[] memory) {
        uint256 length = withdrawalQueueImpls.length;
        address[] memory withdrawalQueueImplsList = new address[](length);

        for (uint256 i; i < length; ++i) {
            withdrawalQueueImplsList[i] = withdrawalQueueImpls[i];
        }

        return withdrawalQueueImplsList;
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
