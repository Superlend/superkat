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

    /// @dev yield aggregator implementation address
    address public immutable yieldAggregatorImpl;
    /// @dev Array for deployed yield aggreagtor addresses.
    address[] public yieldAggregatorVaults;

    event DeployYieldAggregator(address indexed _owner, address _yieldAggregatorVault, address indexed _asset);

    /// @dev Constructor.
    constructor(address _yieldAggregatorImpl) {
        yieldAggregatorImpl = _yieldAggregatorImpl;
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
