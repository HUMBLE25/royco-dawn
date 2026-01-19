// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { MarketDeploymentParams, RoycoMarket } from "../libraries/Types.sol";

/// @title IRoycoFactory
/// @notice Interface for the RoycoFactory contract that deploys Royco markets
interface IRoycoFactory {
    /// @notice Thrown when an invalid name is provided
    error INVALID_NAME();

    /// @notice Thrown when an invalid symbol is provided
    error INVALID_SYMBOL();

    /// @notice Thrown when an invalid asset is provided
    error INVALID_ASSET();

    /// @notice Thrown when an invalid market id is provided
    error INVALID_MARKET_ID();

    /// @notice Thrown when an invalid kernel implementation is provided
    error INVALID_KERNEL_IMPLEMENTATION();

    /// @notice Thrown when an invalid accountant implementation is provided
    error INVALID_ACCOUNTANT_IMPLEMENTATION();

    /// @notice Thrown when an invalid senior tranche proxy deployment salt is provided
    error INVALID_SENIOR_TRANCHE_PROXY_DEPLOYMENT_SALT();

    /// @notice Thrown when an invalid junior tranche proxy deployment salt is provided
    error INVALID_JUNIOR_TRANCHE_PROXY_DEPLOYMENT_SALT();

    /// @notice Thrown when an invalid kernel proxy deployment salt is provided
    error INVALID_KERNEL_PROXY_DEPLOYMENT_SALT();

    /// @notice Thrown when an invalid accountant proxy deployment salt is provided
    error INVALID_ACCOUNTANT_PROXY_DEPLOYMENT_SALT();

    /// @notice Thrown when an invalid senior tranche implementation is provided
    error INVALID_SENIOR_TRANCHE_IMPLEMENTATION();

    /// @notice Thrown when an invalid junior tranche implementation is provided
    error INVALID_JUNIOR_TRANCHE_IMPLEMENTATION();

    /// @notice Thrown when an invalid access manager is configured on a deployed contract
    error INVALID_ACCESS_MANAGER();

    /// @notice Thrown when the kernel address configured on the senior tranche is invalid
    error INVALID_KERNEL_ON_SENIOR_TRANCHE();

    /// @notice Thrown when the kernel address configured on the junior tranche is invalid
    error INVALID_KERNEL_ON_JUNIOR_TRANCHE();

    /// @notice Thrown when the accountant address configured on the kernel is invalid
    error INVALID_ACCOUNTANT_ON_KERNEL();

    /// @notice Thrown when the kernel address configured on the accountant is invalid
    error INVALID_KERNEL_ON_ACCOUNTANT();

    /// @notice Thrown when kernel initialization data is invalid
    error INVALID_KERNEL_INITIALIZATION_DATA();

    /// @notice Thrown when accountant initialization data is invalid
    error INVALID_ACCOUNTANT_INITIALIZATION_DATA();

    /// @notice Thrown when the kernel failed to initialize
    error FAILED_TO_INITIALIZE_KERNEL(bytes data);

    /// @notice Thrown when the accountant failed to initialize
    error FAILED_TO_INITIALIZE_ACCOUNTANT(bytes data);

    /// @notice Thrown when the senior tranche failed to initialize
    error FAILED_TO_INITIALIZE_SENIOR_TRANCHE(bytes data);

    /// @notice Thrown when the junior tranche failed to initialize
    error FAILED_TO_INITIALIZE_JUNIOR_TRANCHE(bytes data);

    /// @notice Thrown when the roles configuration length mismatch
    error ROLES_CONFIGURATION_LENGTH_MISMATCH();

    /// @notice Thrown when the target is invalid
    error INVALID_TARGET(address target);

    /// @notice Emitted when a new market is deployed
    event MarketDeployed(RoycoMarket roycoMarket, MarketDeploymentParams params);

    /// @notice Emitted when a role delay is set
    event RoleDelaySet(uint64 role, uint256 delay);

    /**
     * @notice Deploys a new market with senior tranche, junior tranche, and kernel
     * @param _params The parameters for deploying a new market
     * @param roycoMarket The deployed components constituting the Royco market
     */
    function deployMarket(MarketDeploymentParams calldata _params) external returns (RoycoMarket memory roycoMarket);

    /**
     * @notice Predicts the address of a tranche proxy
     * @param _implementation The implementation address
     * @param _salt The salt for the deployment
     * @return proxy The predicted proxy address
     */
    function predictERC1967ProxyAddress(address _implementation, bytes32 _salt) external view returns (address proxy);
}
