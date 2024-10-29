// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IEulerEarnFactory} from "./interface/IEulerEarnFactory.sol";
// contracts
import {EulerEarn, IEulerEarn} from "./EulerEarn.sol";
// libs
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title EulerEarnFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerEarnFactory is IEulerEarnFactory {
    error InvalidQuery();

    /// @dev Euler earn implementation address
    address public immutable eulerEarnImpl;
    /// @dev Array for deployed Euler Earn addresses.
    address[] public eulerEarnVaults;

    /// @dev Mapping to set a deployed vault as verified.
    mapping(address => bool) internal deployedVault;

    /// @dev Emits when deploying new Earn vault.
    event DeployEulerEarn(address indexed _owner, address _eulerEarnVault, address indexed _asset);

    /// @dev Constructor.
    constructor(address _eulerEarnImpl) {
        eulerEarnImpl = _eulerEarnImpl;
    }

    /// @notice Deploy a new Euler Earn vault.
    /// @param _asset Euler Earn vault's asset address.
    /// @param _name Earn vault name.
    /// @param _symbol Earn vault symbol.
    /// @param _initialCashAllocationPoints The amount of points to initally allocate for cash reserve.
    /// @return The address of the new deployed euler earn.
    function deployEulerEarn(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialCashAllocationPoints
    ) external returns (address) {
        address eulerEulerEarnVault = Clones.clone(eulerEarnImpl);

        IEulerEarn.InitParams memory eulerEarnVaultInitParams = IEulerEarn.InitParams({
            eulerEarnVaultOwner: msg.sender,
            asset: _asset,
            name: _name,
            symbol: _symbol,
            initialCashAllocationPoints: _initialCashAllocationPoints
        });
        IEulerEarn(eulerEulerEarnVault).init(eulerEarnVaultInitParams);

        eulerEarnVaults.push(address(eulerEulerEarnVault));
        deployedVault[address(eulerEulerEarnVault)] = true;

        emit DeployEulerEarn(msg.sender, address(eulerEulerEarnVault), _asset);

        return eulerEulerEarnVault;
    }

    /// @notice Fetch the length of the deployed euler earn vaults list.
    /// @return The length of the euler earn vaults list array.
    function getEulerEarnVaultsListLength() external view returns (uint256) {
        return eulerEarnVaults.length;
    }

    /// @notice Get a slice of the deployed euler earn vaults array.
    /// @param _start Start index of the slice.
    /// @param _end End index of the slice.
    /// @return An array containing the slice of the deployed euler earn vaults list.
    function getEulerEarnVaultsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = eulerEarnVaults.length;
        if (_end == type(uint256).max) _end = length;
        if (_end < _start || _end > length) revert InvalidQuery();

        address[] memory eulerEarnVaultsList = new address[](_end - _start);
        for (uint256 i; i < _end - _start; ++i) {
            eulerEarnVaultsList[i] = eulerEarnVaults[_start + i];
        }

        return eulerEarnVaultsList;
    }

    /// @notice Check if an Euler Earn vault address has been deployed by this factory.
    /// @param _earnVaultAddress Euler Earn address.
    /// @return A boolean, true if vault is deployed by this factory, else false.
    function isValidDeployment(address _earnVaultAddress) external view returns (bool) {
        return deployedVault[_earnVaultAddress];
    }
}
