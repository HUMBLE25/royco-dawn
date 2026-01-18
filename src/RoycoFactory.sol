// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { AccessManagedUpgradeable } from "../lib/openzeppelin-contracts-upgradeable/contracts/access/manager/AccessManagedUpgradeable.sol";
import { AccessManager } from "../lib/openzeppelin-contracts/contracts/access/manager/AccessManager.sol";
import { ERC1967Proxy } from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Create2 } from "../lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import { RoycoRoles } from "./auth/RoycoRoles.sol";
import { IRoycoAccountant } from "./interfaces/IRoycoAccountant.sol";
import { IRoycoFactory } from "./interfaces/IRoycoFactory.sol";
import { IRoycoKernel } from "./interfaces/kernel/IRoycoKernel.sol";
import { IRoycoVaultTranche } from "./interfaces/tranche/IRoycoVaultTranche.sol";
import { DeployedContracts, MarketDeploymentParams, RolesConfiguration } from "./libraries/Types.sol";

/**
 * @title RoycoFactory
 * @notice Factory contract for deploying Royco tranches (ST and JT) and their associated kernel using ERC1967 proxies
 * @notice The factory also acts as the shared access manager for all the Royco market
 * @dev This factory deploys upgradeable tranche contracts using the UUPS proxy pattern
 */
contract RoycoFactory is AccessManager, RoycoRoles, IRoycoFactory {
    /**
     * @notice Initializes the Royco Factory
     * @param _initialAdmin The initial admin of the access manager
     */
    constructor(address _initialAdmin) AccessManager(_initialAdmin) { }

    /// @inheritdoc IRoycoFactory
    function deployMarket(MarketDeploymentParams calldata _params)
        external
        override(IRoycoFactory)
        onlyAuthorized
        returns (DeployedContracts memory deployedContracts)
    {
        // Validate the deployment parameters
        _validateDeploymentParams(_params);

        // Deploy the contracts
        deployedContracts = _deployContracts(_params);

        // Validate the deployment
        _validateDeployment(deployedContracts);

        // Configure the roles
        _configureRoles(deployedContracts, _params.roles);

        emit MarketDeployed(deployedContracts, _params);
    }

    /// @inheritdoc IRoycoFactory
    function predictERC1967ProxyAddress(address _implementation, bytes32 _salt) external view override(IRoycoFactory) returns (address proxy) {
        proxy = Create2.computeAddress(_salt, keccak256(abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_implementation, ""))));
    }

    /**
     * @notice Deploys the contracts for a new market
     * @param _params The parameters for deploying a new market
     * @return deployedContracts The deployed contracts
     */
    function _deployContracts(MarketDeploymentParams calldata _params) internal virtual returns (DeployedContracts memory deployedContracts) {
        // Deploy the kernel, accountant and tranches with empty initialization data
        // It is expected that the kernel initialization data contains the address of the accountant and vice versa
        // Therefore, it is expected that the proxy address is precomputed based on an uninitialized erc1967 proxy initcode
        // and that the proxy is initalized separately after deployment, in the same transaction

        // Deploy the accountant with empty initialization data
        deployedContracts.accountant =
            IRoycoAccountant(_deployERC1967ProxyDeterministic(address(_params.accountantImplementation), _params.accountantProxyDeploymentSalt));

        // Deploy the kernel with empty initialization data
        deployedContracts.kernel = IRoycoKernel(_deployERC1967ProxyDeterministic(address(_params.kernelImplementation), _params.kernelProxyDeploymentSalt));

        // Deploy the senior tranche with empty initialization data
        deployedContracts.seniorTranche =
            IRoycoVaultTranche(_deployERC1967ProxyDeterministic(address(_params.seniorTrancheImplementation), _params.seniorTrancheProxyDeploymentSalt));

        // Deploy the junior tranche with empty initialization data
        deployedContracts.juniorTranche =
            IRoycoVaultTranche(_deployERC1967ProxyDeterministic(address(_params.juniorTrancheImplementation), _params.juniorTrancheProxyDeploymentSalt));

        // Initialize the senior tranche
        (bool success, bytes memory data) = address(deployedContracts.seniorTranche).call(_params.seniorTrancheInitializationData);
        require(success, FAILED_TO_INITIALIZE_SENIOR_TRANCHE(data));

        // Initialize the junior tranche
        (success, data) = address(deployedContracts.juniorTranche).call(_params.juniorTrancheInitializationData);
        require(success, FAILED_TO_INITIALIZE_JUNIOR_TRANCHE(data));

        // Initialize the accountant
        (success, data) = address(deployedContracts.accountant).call(_params.accountantInitializationData);
        require(success, FAILED_TO_INITIALIZE_ACCOUNTANT(data));

        // Initialize the kernel
        (success, data) = address(deployedContracts.kernel).call(_params.kernelInitializationData);
        require(success, FAILED_TO_INITIALIZE_KERNEL(data));
    }

    /// @notice Validates the deployments
    /// @param _deployedContracts The deployed contracts to validate
    function _validateDeployment(DeployedContracts memory _deployedContracts) internal view {
        // Check that the access manager is set on the contracts
        require(AccessManagedUpgradeable(address(_deployedContracts.accountant)).authority() == address(this), INVALID_ACCESS_MANAGER());
        require(AccessManagedUpgradeable(address(_deployedContracts.kernel)).authority() == address(this), INVALID_ACCESS_MANAGER());
        require(AccessManagedUpgradeable(address(_deployedContracts.seniorTranche)).authority() == address(this), INVALID_ACCESS_MANAGER());
        require(AccessManagedUpgradeable(address(_deployedContracts.juniorTranche)).authority() == address(this), INVALID_ACCESS_MANAGER());

        // Check that the kernel is set on the tranches
        require(address(_deployedContracts.seniorTranche.kernel()) == address(_deployedContracts.kernel), INVALID_KERNEL_ON_SENIOR_TRANCHE());
        require(address(_deployedContracts.juniorTranche.kernel()) == address(_deployedContracts.kernel), INVALID_KERNEL_ON_JUNIOR_TRANCHE());

        (,,,,, address accountant,) = _deployedContracts.kernel.getState();
        // Check that the accountant is set on the kernel
        require(address(accountant) == address(_deployedContracts.accountant), INVALID_ACCOUNTANT_ON_KERNEL());

        // Check that the kernel is set on the accountant
        require(address(_deployedContracts.accountant.getState().kernel) == address(_deployedContracts.kernel), INVALID_KERNEL_ON_ACCOUNTANT());
    }

    /// @notice Validates the deployment parameters
    /// @param _params The parameters to validate
    function _validateDeploymentParams(MarketDeploymentParams calldata _params) internal pure {
        require(bytes(_params.seniorTrancheName).length > 0, INVALID_NAME());
        require(bytes(_params.seniorTrancheSymbol).length > 0, INVALID_SYMBOL());
        require(bytes(_params.juniorTrancheName).length > 0, INVALID_NAME());
        require(bytes(_params.juniorTrancheSymbol).length > 0, INVALID_SYMBOL());
        require(_params.seniorAsset != address(0), INVALID_ASSET());
        require(_params.juniorAsset != address(0), INVALID_ASSET());
        require(_params.marketId != bytes32(0), INVALID_MARKET_ID());
        // Validate the implementation addresses
        require(address(_params.kernelImplementation) != address(0), INVALID_KERNEL_IMPLEMENTATION());
        require(address(_params.accountantImplementation) != address(0), INVALID_ACCOUNTANT_IMPLEMENTATION());
        // Validate the initialization data
        require(_params.kernelInitializationData.length > 0, INVALID_KERNEL_INITIALIZATION_DATA());
        require(_params.accountantInitializationData.length > 0, INVALID_ACCOUNTANT_INITIALIZATION_DATA());
        // Validate the deployment salts
        require(_params.seniorTrancheProxyDeploymentSalt != bytes32(0), INVALID_SENIOR_TRANCHE_PROXY_DEPLOYMENT_SALT());
        require(_params.juniorTrancheProxyDeploymentSalt != bytes32(0), INVALID_JUNIOR_TRANCHE_PROXY_DEPLOYMENT_SALT());
        require(_params.kernelProxyDeploymentSalt != bytes32(0), INVALID_KERNEL_PROXY_DEPLOYMENT_SALT());
        require(_params.accountantProxyDeploymentSalt != bytes32(0), INVALID_ACCOUNTANT_PROXY_DEPLOYMENT_SALT());
    }

    /**
     * @notice Configures the roles for the deployed contracts
     * @param _deployedContracts The deployed contracts to configure
     * @param _roles The roles to configure
     */
    function _configureRoles(DeployedContracts memory _deployedContracts, RolesConfiguration[] calldata _roles) internal {
        for (uint256 i = 0; i < _roles.length; ++i) {
            RolesConfiguration calldata role = _roles[i];

            // Validate that the selectors and roles length match
            require(role.selectors.length == role.roles.length, ROLES_CONFIGURATION_LENGTH_MISMATCH());

            // Validate that the target is one of the deployed contracts
            address target = role.target;
            require(
                target == address(_deployedContracts.accountant) || target == address(_deployedContracts.kernel)
                    || target == address(_deployedContracts.seniorTranche) || target == address(_deployedContracts.juniorTranche),
                INVALID_TARGET(target)
            );

            for (uint256 j = 0; j < role.selectors.length; ++j) {
                _setTargetFunctionRole(target, role.selectors[j], role.roles[j]);
            }
        }
    }

    /**
     * @notice Deploys a tranche using ERC1967 proxy deterministically
     * @param _implementation The implementation address
     * @param _salt The salt for the deployment
     *  @return proxy The deployed proxy address
     */
    function _deployERC1967ProxyDeterministic(address _implementation, bytes32 _salt) internal returns (address proxy) {
        proxy = Create2.deploy(0, _salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_implementation, "")));
    }
}
