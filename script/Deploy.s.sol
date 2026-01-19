// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "../lib/openzeppelin-contracts/contracts/access/manager/IAccessManager.sol";
import { UUPSUpgradeable } from "../lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import { RoycoFactory } from "../src/RoycoFactory.sol";
import { RoycoAccountant } from "../src/accountant/RoycoAccountant.sol";
import { RoycoRoles } from "../src/auth/RoycoRoles.sol";
import { IRoycoAccountant } from "../src/interfaces/IRoycoAccountant.sol";
import { IRoycoAuth } from "../src/interfaces/IRoycoAuth.sol";
import { IYDM } from "../src/interfaces/IYDM.sol";
import { IRoycoKernel } from "../src/interfaces/kernel/IRoycoKernel.sol";
import { IRoycoAsyncCancellableVault } from "../src/interfaces/tranche/IRoycoAsyncCancellableVault.sol";
import { IRoycoAsyncVault } from "../src/interfaces/tranche/IRoycoAsyncVault.sol";
import { IRoycoVaultTranche } from "../src/interfaces/tranche/IRoycoVaultTranche.sol";
import { ERC4626_ST_AaveV3_JT_InKindAssets_Kernel } from "../src/kernels/ERC4626_ST_AaveV3_JT_InKindAssets_Kernel.sol";
import { ERC4626_ST_ERC4626_JT_InKindAssets_Kernel } from "../src/kernels/ERC4626_ST_ERC4626_JT_InKindAssets_Kernel.sol";
import { ReUSD_ST_ReUSD_JT_Kernel } from "../src/kernels/ReUSD_ST_ReUSD_JT_Kernel.sol";
import {
    YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel
} from "../src/kernels/YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel.sol";
import {
    YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel
} from "../src/kernels/YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel.sol";
import { RoycoKernelInitParams } from "../src/libraries/RoycoKernelStorageLib.sol";
import { AssetClaims, MarketDeploymentParams, RolesConfiguration, RoycoMarket, TrancheDeploymentParams } from "../src/libraries/Types.sol";
import { TRANCHE_UNIT } from "../src/libraries/Units.sol";
import { RoycoJuniorTranche } from "../src/tranches/RoycoJuniorTranche.sol";
import { RoycoSeniorTranche } from "../src/tranches/RoycoSeniorTranche.sol";
import { AdaptiveCurveYDM } from "../src/ydm/AdaptiveCurveYDM.sol";
import { StaticCurveYDM } from "../src/ydm/StaticCurveYDM.sol";
import { Create2DeployUtils } from "./Create2DeployUtils.sol";
import { Script } from "lib/forge-std/src/Script.sol";
import { console2 } from "lib/forge-std/src/console2.sol";

/// @notice Interface for kernel oracle quoter admin functions
interface IKernelOracleQuoterAdmin {
    function setConversionRate(uint256 _conversionRateRAY) external;
    function setTrancheAssetToReferenceAssetOracle(address _trancheAssetToReferenceAssetOracle, uint48 _stalenessThresholdSeconds) external;
}

contract DeployScript is Script, Create2DeployUtils, RoycoRoles {
    // Custom errors
    error UnsupportedKernelType(KernelType kernelType);
    error UnsupportedYDMType(YDMType ydmType);
    error DeployerNotFactoryAdmin(address deployer);

    // Deployment salts for CREATE2
    bytes32 constant ACCOUNTANT_IMPL_SALT = keccak256("ROYCO_ACCOUNTANT_IMPLEMENTATION_V1");
    bytes32 constant KERNEL_IMPL_SALT = keccak256("ROYCO_KERNEL_IMPLEMENTATION_V1");
    bytes32 constant ST_TRANCHE_IMPL_SALT = keccak256("ROYCO_ST_TRANCHE_IMPLEMENTATION_V1");
    bytes32 constant JT_TRANCHE_IMPL_SALT = keccak256("ROYCO_JT_TRANCHE_IMPLEMENTATION_V1");
    bytes32 constant YDM_SALT = keccak256("ROYCO_YDM_IMPLEMENTATION_V1");
    bytes32 constant FACTORY_SALT_BASE = keccak256("ROYCO_FACTORY_IMPLEMENTATION_V1");
    bytes32 constant MARKET_DEPLOYMENT_SALT = keccak256("ROYCO_MARKET_DEPLOYMENT_V2");

    /// @notice Enum for kernel types
    enum KernelType {
        ERC4626_ST_AaveV3_JT_InKindAssets,
        ERC4626_ST_ERC4626_JT_InKindAssets,
        ReUSD_ST_ReUSD_JT,
        YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter,
        YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets
    }

    /// @notice Enum for YDM types
    enum YDMType {
        StaticCurve,
        AdaptiveCurve
    }

    /// @notice Deployment parameters for ERC4626_ST_AaveV3_JT_InKindAssets_Kernel
    struct ERC4626STAaveV3JTInKindAssetsKernelParams {
        address stVault;
        address aaveV3Pool;
    }

    /// @notice Deployment parameters for ERC4626_ST_ERC4626_JT_InKindAssets_Kernel
    struct ERC4626STERC4626JTInKindAssetsKernelParams {
        address stVault;
        address jtVault;
    }

    /// @notice Deployment parameters for ReUSD_ST_ReUSD_JT_Kernel
    struct ReUSDSTReUSDJTKernelParams {
        address reusd;
        address reusdUsdQuoteToken;
        address insuranceCapitalLayer;
    }

    /// @notice Deployment parameters for YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel
    struct YieldBearingERC20STYieldBearingERC20JTIdenticalAssetsChainlinkOracleQuoterKernelParams {
        address trancheAssetToReferenceAssetOracle;
        uint48 stalenessThresholdSeconds;
        uint256 initialConversionRateWAD;
    }

    /// @notice Deployment parameters for YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel
    struct YieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626AssetsKernelParams {
        uint256 initialConversionRateWAD;
    }

    /// @notice Deployment parameters for StaticCurveYDM
    struct StaticCurveYDMParams {
        uint64 jtYieldShareAtZeroUtilWAD;
        uint64 jtYieldShareAtTargetUtilWAD;
        uint64 jtYieldShareAtFullUtilWAD;
    }

    /// @notice Deployment parameters for AdaptiveCurveYDM
    struct AdaptiveCurveYDMParams {
        uint64 jtYieldShareAtTargetUtilWAD;
        uint64 jtYieldShareAtFullUtilWAD;
    }

    /// @notice Complete deployment result containing all deployed contracts
    struct DeploymentResult {
        RoycoFactory factory;
        RoycoAccountant accountantImplementation;
        RoycoSeniorTranche stTrancheImplementation;
        RoycoJuniorTranche jtTrancheImplementation;
        address kernelImplementation;
        IYDM ydm;
        IRoycoVaultTranche seniorTranche;
        IRoycoVaultTranche juniorTranche;
        IRoycoAccountant accountant;
        IRoycoKernel kernel;
        bytes32 marketId;
    }

    /// @notice Main deployment parameters struct
    struct DeploymentParams {
        // Factory params
        address factoryAdmin;
        address factoryOwnerAddress;
        // Market params
        bytes32 marketId;
        string seniorTrancheName;
        string seniorTrancheSymbol;
        string juniorTrancheName;
        string juniorTrancheSymbol;
        address seniorAsset;
        address juniorAsset;
        // Kernel params
        KernelType kernelType;
        bytes kernelSpecificParams; // Encoded kernel-specific params
        // Kernel initialization params
        address protocolFeeRecipient;
        uint24 jtRedemptionDelayInSeconds;
        // Accountant params
        uint64 stProtocolFeeWAD;
        uint64 jtProtocolFeeWAD;
        uint64 coverageWAD;
        uint96 betaWAD;
        uint64 lltvWAD;
        uint24 fixedTermDurationSeconds;
        // YDM params
        YDMType ydmType;
        bytes ydmSpecificParams; // Encoded YDM-specific params
        // Roles
        address pauserAddress;
        uint32 pauserExecutionDelay;
        address upgraderAddress;
        uint32 upgraderExecutionDelay;
        address lpRoleAddress;
        uint32 lpRoleExecutionDelay;
        address syncRoleAddress;
        uint32 syncRoleExecutionDelay;
        address kernelAdminRoleAddress;
        uint32 kernelAdminRoleExecutionDelay;
        address oracleQuoterAdminRoleAddress;
        uint32 oracleQuoterAdminRoleExecutionDelay;
    }

    function run() external {
        // Read deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Read all deployment parameters from environment variables
        DeploymentParams memory params = _readDeploymentParamsFromEnv();

        // Deploy using the main deploy function
        deploy(params);

        vm.stopBroadcast();
    }

    /// @notice Main deployment function that accepts all parameters
    function deploy(DeploymentParams memory _params) public returns (DeploymentResult memory) {
        // Deploy implementations using CREATE2
        RoycoAccountant accountantImpl = _deployAccountantImpl();
        RoycoSeniorTranche stTrancheImpl = _deploySTTrancheImpl();
        RoycoJuniorTranche jtTrancheImpl = _deployJTTrancheImpl();
        IYDM ydm = _deployYDM(_params.ydmType);
        RoycoFactory factory = _deployFactory(_params.factoryAdmin);

        // Deploy market using factory (kernel implementation is deployed inside _deployMarket)
        (RoycoMarket memory market, address kernelImpl) = _deployMarket(factory, accountantImpl, stTrancheImpl, jtTrancheImpl, address(ydm), _params);

        // Transfer factory ownership to new admin if provided
        _transferFactoryOwnership(factory, _params.factoryOwnerAddress);

        // Build deployment result
        DeploymentResult memory result = DeploymentResult({
            factory: factory,
            accountantImplementation: accountantImpl,
            stTrancheImplementation: stTrancheImpl,
            jtTrancheImplementation: jtTrancheImpl,
            kernelImplementation: kernelImpl,
            ydm: ydm,
            seniorTranche: market.seniorTranche,
            juniorTranche: market.juniorTranche,
            accountant: market.accountant,
            kernel: market.kernel,
            marketId: _params.marketId
        });

        // Log all deployed contracts
        console2.log("=== Deployment Summary ===");
        console2.log("Factory:", address(result.factory));
        console2.log("Factory Admin:", _params.factoryAdmin);
        console2.log("Factory Owner:", _params.factoryOwnerAddress);
        console2.log("YDM:", address(result.ydm));
        console2.log("Accountant Implementation:", address(result.accountantImplementation));
        console2.log("ST Tranche Implementation:", address(result.stTrancheImplementation));
        console2.log("JT Tranche Implementation:", address(result.jtTrancheImplementation));
        console2.log("Kernel Implementation:", result.kernelImplementation);
        console2.log("Senior Tranche (Proxy):", address(result.seniorTranche));
        console2.log("Junior Tranche (Proxy):", address(result.juniorTranche));
        console2.log("Accountant (Proxy):", address(result.accountant));
        console2.log("Kernel (Proxy):", address(result.kernel));
        console2.log("Market ID:", uint256(_params.marketId));
        console2.log("========================");

        return result;
    }

    /// @notice Builds the roles configuration for a market
    /// @param _seniorTranche The senior tranche address
    /// @param _juniorTranche The junior tranche address
    /// @param _kernel The kernel address
    /// @param _accountant The accountant address
    /// @return roles The roles configuration array
    function buildRolesConfiguration(
        address _seniorTranche,
        address _juniorTranche,
        address _kernel,
        address _accountant
    )
        public
        pure
        returns (RolesConfiguration[] memory roles)
    {
        // Count how many role configurations we need
        uint256 roleCount = 4; // ST, JT, Kernel, Accountant

        roles = new RolesConfiguration[](roleCount);
        uint256 index = 0;

        // Senior Tranche roles
        bytes4[] memory stSelectors = new bytes4[](13);
        uint64[] memory stRoles = new uint64[](13);

        stSelectors[0] = IRoycoVaultTranche.deposit.selector;
        stRoles[0] = LP_ROLE;
        stSelectors[1] = IRoycoVaultTranche.redeem.selector;
        stRoles[1] = LP_ROLE;
        stSelectors[2] = IRoycoAsyncVault.requestDeposit.selector;
        stRoles[2] = LP_ROLE;
        stSelectors[3] = IRoycoAsyncVault.requestRedeem.selector;
        stRoles[3] = LP_ROLE;
        stSelectors[4] = IRoycoAsyncCancellableVault.cancelDepositRequest.selector;
        stRoles[4] = LP_ROLE;
        stSelectors[5] = IRoycoAsyncCancellableVault.claimCancelDepositRequest.selector;
        stRoles[5] = LP_ROLE;
        stSelectors[6] = IRoycoAsyncCancellableVault.cancelRedeemRequest.selector;
        stRoles[6] = LP_ROLE;
        stSelectors[7] = IRoycoAsyncCancellableVault.claimCancelRedeemRequest.selector;
        stRoles[7] = LP_ROLE;
        stSelectors[8] = IRoycoAuth.pause.selector;
        stRoles[8] = ADMIN_PAUSER_ROLE;
        stSelectors[9] = IRoycoAuth.unpause.selector;
        stRoles[9] = ADMIN_PAUSER_ROLE;
        stSelectors[10] = bytes4(0xe4cca4b0);
        stRoles[10] = LP_ROLE;
        stSelectors[11] = bytes4(0x9f40a7b3);
        stRoles[11] = LP_ROLE;
        stSelectors[12] = UUPSUpgradeable.upgradeToAndCall.selector;
        stRoles[12] = ADMIN_UPGRADER_ROLE;

        roles[index++] = RolesConfiguration({ target: _seniorTranche, selectors: stSelectors, roles: stRoles });

        // Junior Tranche roles (same as senior)
        bytes4[] memory jtSelectors = stSelectors;
        uint64[] memory jtRoles = stRoles;

        roles[index++] = RolesConfiguration({ target: _juniorTranche, selectors: jtSelectors, roles: jtRoles });

        // Kernel roles
        bytes4[] memory kernelSelectors = new bytes4[](8);
        uint64[] memory kernelRoleValues = new uint64[](8);

        kernelSelectors[0] = IRoycoKernel.setProtocolFeeRecipient.selector;
        kernelRoleValues[0] = ADMIN_KERNEL_ROLE;
        kernelSelectors[1] = IRoycoKernel.syncTrancheAccounting.selector;
        kernelRoleValues[1] = SYNC_ROLE;
        kernelSelectors[2] = IRoycoAuth.pause.selector;
        kernelRoleValues[2] = ADMIN_PAUSER_ROLE;
        kernelSelectors[3] = IRoycoAuth.unpause.selector;
        kernelRoleValues[3] = ADMIN_PAUSER_ROLE;
        kernelSelectors[4] = IRoycoKernel.setJuniorTrancheRedemptionDelay.selector;
        kernelRoleValues[4] = ADMIN_KERNEL_ROLE;
        // Quoter admin functions (only present in kernels with oracle quoters)
        kernelSelectors[5] = bytes4(0xd2e80494); // setConversionRate(uint256)
        kernelRoleValues[5] = ADMIN_ORACLE_QUOTER_ROLE;
        kernelSelectors[6] = bytes4(0x8138d87d); // setTrancheAssetToReferenceAssetOracle(address,uint48)
        kernelRoleValues[6] = ADMIN_ORACLE_QUOTER_ROLE;
        kernelSelectors[7] = UUPSUpgradeable.upgradeToAndCall.selector;
        kernelRoleValues[7] = ADMIN_UPGRADER_ROLE;

        roles[index++] = RolesConfiguration({ target: _kernel, selectors: kernelSelectors, roles: kernelRoleValues });

        // Accountant roles
        bytes4[] memory accountantSelectors = new bytes4[](10);
        uint64[] memory accountantRoleValues = new uint64[](10);

        accountantSelectors[0] = IRoycoAccountant.setYDM.selector;
        accountantRoleValues[0] = ADMIN_KERNEL_ROLE;
        accountantSelectors[1] = IRoycoAccountant.setSeniorTrancheProtocolFee.selector;
        accountantRoleValues[1] = ADMIN_KERNEL_ROLE;
        accountantSelectors[2] = IRoycoAccountant.setJuniorTrancheProtocolFee.selector;
        accountantRoleValues[2] = ADMIN_KERNEL_ROLE;
        accountantSelectors[3] = IRoycoAccountant.setCoverage.selector;
        accountantRoleValues[3] = ADMIN_KERNEL_ROLE;
        accountantSelectors[4] = IRoycoAccountant.setBeta.selector;
        accountantRoleValues[4] = ADMIN_KERNEL_ROLE;
        accountantSelectors[5] = IRoycoAccountant.setLLTV.selector;
        accountantRoleValues[5] = ADMIN_KERNEL_ROLE;
        accountantSelectors[6] = IRoycoAccountant.setFixedTermDuration.selector;
        accountantRoleValues[6] = ADMIN_KERNEL_ROLE;
        accountantSelectors[7] = IRoycoAuth.pause.selector;
        accountantRoleValues[7] = ADMIN_PAUSER_ROLE;
        accountantSelectors[8] = IRoycoAuth.unpause.selector;
        accountantRoleValues[8] = ADMIN_PAUSER_ROLE;
        accountantSelectors[9] = UUPSUpgradeable.upgradeToAndCall.selector;
        accountantRoleValues[9] = ADMIN_UPGRADER_ROLE;

        roles[index++] = RolesConfiguration({ target: _accountant, selectors: accountantSelectors, roles: accountantRoleValues });
    }

    /// @notice Grants all relevant roles to the addresses specified in the deployment parameters
    /// @param _factory The factory contract (which acts as the AccessManager)
    /// @param _params The deployment parameters containing role addresses
    function grantAllRoles(RoycoFactory _factory, DeploymentParams memory _params) public {
        IAccessManager accessManager = IAccessManager(address(_factory));

        console2.log("Granting roles on AccessManager:", address(_factory));

        // Grant ADMIN_PAUSER_ROLE (used by ST, JT, Kernel, Accountant)
        accessManager.grantRole(ADMIN_PAUSER_ROLE, _params.pauserAddress, _params.pauserExecutionDelay);
        console2.log("  - ADMIN_PAUSER_ROLE granted to:", _params.pauserAddress, "with delay:", _params.pauserExecutionDelay);

        // Grant ADMIN_UPGRADER_ROLE (used by ST, JT, Kernel, Accountant for UUPS upgrades)
        accessManager.grantRole(ADMIN_UPGRADER_ROLE, _params.upgraderAddress, _params.upgraderExecutionDelay);
        console2.log("  - ADMIN_UPGRADER_ROLE granted to:", _params.upgraderAddress, "with delay:", _params.upgraderExecutionDelay);

        // Grant LP_ROLE (used by ST, JT)
        accessManager.grantRole(LP_ROLE, _params.lpRoleAddress, _params.lpRoleExecutionDelay);
        console2.log("  - LP_ROLE granted to:", _params.lpRoleAddress, "with delay:", _params.lpRoleExecutionDelay);

        // Grant SYNC_ROLE (used by Kernel)
        accessManager.grantRole(SYNC_ROLE, _params.syncRoleAddress, _params.syncRoleExecutionDelay);
        console2.log("  - SYNC_ROLE granted to:", _params.syncRoleAddress, "with delay:", _params.syncRoleExecutionDelay);

        // Grant ADMIN_KERNEL_ROLE (used by Kernel, Accountant)
        accessManager.grantRole(ADMIN_KERNEL_ROLE, _params.kernelAdminRoleAddress, _params.kernelAdminRoleExecutionDelay);
        console2.log("  - ADMIN_KERNEL_ROLE granted to:", _params.kernelAdminRoleAddress, "with delay:", _params.kernelAdminRoleExecutionDelay);

        // Grant ADMIN_ORACLE_QUOTER_ROLE (used by Kernel quoters)
        accessManager.grantRole(ADMIN_ORACLE_QUOTER_ROLE, _params.oracleQuoterAdminRoleAddress, _params.oracleQuoterAdminRoleExecutionDelay);
        console2.log(
            "  - ADMIN_ORACLE_QUOTER_ROLE granted to:", _params.oracleQuoterAdminRoleAddress, "with delay:", _params.oracleQuoterAdminRoleExecutionDelay
        );

        console2.log("All roles granted successfully!");
    }

    /// @notice Deploys all contracts for a market
    /// @param factory The deployed factory
    /// @param accountantImpl The deployed accountant implementation
    /// @param stTrancheImpl The deployed ST tranche implementation
    /// @param jtTrancheImpl The deployed JT tranche implementation
    /// @param ydmAddress The address of the deployed YDM
    /// @param _params The deployment parameters
    /// @return deployedContracts The deployed market contracts
    /// @return kernelImpl The deployed kernel implementation address
    function _deployMarket(
        RoycoFactory factory,
        RoycoAccountant accountantImpl,
        RoycoSeniorTranche stTrancheImpl,
        RoycoJuniorTranche jtTrancheImpl,
        address ydmAddress,
        DeploymentParams memory _params
    )
        internal
        returns (RoycoMarket memory, address)
    {
        // Precompute expected proxy addresses using inline salt
        bytes32 salt = MARKET_DEPLOYMENT_SALT;
        address expectedSeniorTrancheAddress = factory.predictERC1967ProxyAddress(address(stTrancheImpl), salt);
        address expectedJuniorTrancheAddress = factory.predictERC1967ProxyAddress(address(jtTrancheImpl), salt);
        address expectedAccountantAddress = factory.predictERC1967ProxyAddress(address(accountantImpl), salt);

        // Deploy the kernel implementation based on kernel type
        address kernelImpl = _deployKernelImpl(
            _params.kernelType,
            _params.kernelSpecificParams,
            expectedSeniorTrancheAddress,
            expectedJuniorTrancheAddress,
            _params.seniorAsset,
            _params.juniorAsset
        );
        address expectedKernelAddress = factory.predictERC1967ProxyAddress(address(kernelImpl), salt);

        console2.log("Expected Senior Tranche Address:", expectedSeniorTrancheAddress);
        console2.log("Expected Junior Tranche Address:", expectedJuniorTrancheAddress);
        console2.log("Expected Kernel Address:", expectedKernelAddress);
        console2.log("Expected Accountant Address:", expectedAccountantAddress);

        // Build initialization data
        address factoryAddress = address(factory);
        bytes memory kernelInitializationData =
            _buildKernelInitializationData(_params.kernelType, _params.kernelSpecificParams, expectedAccountantAddress, factoryAddress, _params);
        bytes memory accountantInitializationData = _buildAccountantInitializationData(expectedKernelAddress, ydmAddress, factoryAddress, _params);
        bytes memory seniorTrancheInitializationData = _buildSeniorTrancheInitializationData(expectedKernelAddress, _params.marketId, factoryAddress, _params);
        bytes memory juniorTrancheInitializationData = _buildJuniorTrancheInitializationData(expectedKernelAddress, _params.marketId, factoryAddress, _params);

        // Build roles configuration
        RolesConfiguration[] memory roles =
            buildRolesConfiguration(expectedSeniorTrancheAddress, expectedJuniorTrancheAddress, expectedKernelAddress, expectedAccountantAddress);

        // Build market deployment params
        MarketDeploymentParams memory marketParams = MarketDeploymentParams({
            seniorTrancheName: _params.seniorTrancheName,
            seniorTrancheSymbol: _params.seniorTrancheSymbol,
            juniorTrancheName: _params.juniorTrancheName,
            juniorTrancheSymbol: _params.juniorTrancheSymbol,
            marketId: _params.marketId,
            seniorTrancheImplementation: IRoycoVaultTranche(address(stTrancheImpl)),
            juniorTrancheImplementation: IRoycoVaultTranche(address(jtTrancheImpl)),
            kernelImplementation: IRoycoKernel(address(kernelImpl)),
            accountantImplementation: IRoycoAccountant(address(accountantImpl)),
            seniorTrancheInitializationData: seniorTrancheInitializationData,
            juniorTrancheInitializationData: juniorTrancheInitializationData,
            kernelInitializationData: kernelInitializationData,
            accountantInitializationData: accountantInitializationData,
            seniorTrancheProxyDeploymentSalt: salt,
            juniorTrancheProxyDeploymentSalt: salt,
            kernelProxyDeploymentSalt: salt,
            accountantProxyDeploymentSalt: salt,
            roles: roles
        });

        // Deploy market
        console2.log("Deploying market...");
        RoycoMarket memory deployedContracts = factory.deployMarket(marketParams);

        console2.log("Market deployed successfully!");
        console2.log("Senior Tranche:", address(deployedContracts.seniorTranche));
        console2.log("Junior Tranche:", address(deployedContracts.juniorTranche));
        console2.log("Kernel:", address(deployedContracts.kernel));
        console2.log("Accountant:", address(deployedContracts.accountant));

        // Grant all roles to the specified addresses
        grantAllRoles(factory, _params);

        return (deployedContracts, kernelImpl);
    }

    /// @notice Reads all deployment parameters from environment variables
    function _readDeploymentParamsFromEnv() internal view returns (DeploymentParams memory) {
        KernelType kernelType = KernelType(vm.envUint("KERNEL_TYPE"));

        bytes memory kernelSpecificParams;
        if (kernelType == KernelType.ERC4626_ST_AaveV3_JT_InKindAssets) {
            ERC4626STAaveV3JTInKindAssetsKernelParams memory kernelParams =
                ERC4626STAaveV3JTInKindAssetsKernelParams({ stVault: vm.envAddress("ST_VAULT_ADDRESS"), aaveV3Pool: vm.envAddress("AAVE_V3_POOL_ADDRESS") });
            kernelSpecificParams = abi.encode(kernelParams);
        } else if (kernelType == KernelType.ERC4626_ST_ERC4626_JT_InKindAssets) {
            ERC4626STERC4626JTInKindAssetsKernelParams memory kernelParams =
                ERC4626STERC4626JTInKindAssetsKernelParams({ stVault: vm.envAddress("ST_VAULT_ADDRESS"), jtVault: vm.envAddress("JT_VAULT_ADDRESS") });
            kernelSpecificParams = abi.encode(kernelParams);
        } else if (kernelType == KernelType.ReUSD_ST_ReUSD_JT) {
            ReUSDSTReUSDJTKernelParams memory kernelParams = ReUSDSTReUSDJTKernelParams({
                reusd: vm.envAddress("REUSD_ADDRESS"),
                reusdUsdQuoteToken: vm.envAddress("REUSD_USD_QUOTE_TOKEN_ADDRESS"),
                insuranceCapitalLayer: vm.envAddress("INSURANCE_CAPITAL_LAYER_ADDRESS")
            });
            kernelSpecificParams = abi.encode(kernelParams);
        } else if (kernelType == KernelType.YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter) {
            YieldBearingERC20STYieldBearingERC20JTIdenticalAssetsChainlinkOracleQuoterKernelParams memory kernelParams =
                YieldBearingERC20STYieldBearingERC20JTIdenticalAssetsChainlinkOracleQuoterKernelParams({
                    trancheAssetToReferenceAssetOracle: vm.envAddress("TRANCHE_ASSET_TO_REFERENCE_ASSET_ORACLE_ADDRESS"),
                    stalenessThresholdSeconds: uint48(vm.envUint("STALENESS_THRESHOLD_SECONDS")),
                    initialConversionRateWAD: vm.envUint("INITIAL_CONVERSION_RATE_WAD")
                });
            kernelSpecificParams = abi.encode(kernelParams);
        } else if (kernelType == KernelType.YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets) {
            YieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626AssetsKernelParams memory kernelParams =
                YieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626AssetsKernelParams({
                    initialConversionRateWAD: vm.envUint("INITIAL_CONVERSION_RATE_WAD")
                });
            kernelSpecificParams = abi.encode(kernelParams);
        }

        return DeploymentParams({
            factoryAdmin: vm.envAddress("FACTORY_ADMIN"),
            factoryOwnerAddress: vm.envAddress("FACTORY_OWNER_ADDRESS"),
            marketId: vm.envBytes32("MARKET_ID"),
            seniorTrancheName: vm.envString("SENIOR_TRANCHE_NAME"),
            seniorTrancheSymbol: vm.envString("SENIOR_TRANCHE_SYMBOL"),
            juniorTrancheName: vm.envString("JUNIOR_TRANCHE_NAME"),
            juniorTrancheSymbol: vm.envString("JUNIOR_TRANCHE_SYMBOL"),
            seniorAsset: vm.envAddress("SENIOR_ASSET"),
            juniorAsset: vm.envAddress("JUNIOR_ASSET"),
            kernelType: kernelType,
            kernelSpecificParams: kernelSpecificParams,
            protocolFeeRecipient: vm.envAddress("PROTOCOL_FEE_RECIPIENT"),
            jtRedemptionDelayInSeconds: uint24(vm.envUint("JT_REDEMPTION_DELAY_SECONDS")),
            stProtocolFeeWAD: uint64(vm.envUint("ST_PROTOCOL_FEE_WAD")),
            jtProtocolFeeWAD: uint64(vm.envUint("JT_PROTOCOL_FEE_WAD")),
            coverageWAD: uint64(vm.envUint("COVERAGE_WAD")),
            betaWAD: uint96(vm.envUint("BETA_WAD")),
            lltvWAD: uint64(vm.envUint("LLTV_WAD")),
            fixedTermDurationSeconds: uint24(vm.envUint("FIXED_TERM_DURATION_SECONDS")),
            ydmType: YDMType(vm.envUint("YDM_TYPE")),
            ydmSpecificParams: _readYDMParamsFromEnv(YDMType(vm.envUint("YDM_TYPE"))),
            pauserAddress: vm.envAddress("PAUSER_ADDRESS"),
            pauserExecutionDelay: uint32(vm.envUint("PAUSER_EXECUTION_DELAY")),
            upgraderAddress: vm.envAddress("UPGRADER_ADDRESS"),
            upgraderExecutionDelay: uint32(vm.envUint("UPGRADER_EXECUTION_DELAY")),
            lpRoleAddress: vm.envAddress("LP_ROLE_ADDRESS"),
            lpRoleExecutionDelay: uint32(vm.envUint("LP_ROLE_EXECUTION_DELAY")),
            syncRoleAddress: vm.envAddress("SYNC_ROLE_ADDRESS"),
            syncRoleExecutionDelay: uint32(vm.envUint("SYNC_ROLE_EXECUTION_DELAY")),
            kernelAdminRoleAddress: vm.envAddress("ADMIN_KERNEL_ROLE_ADDRESS"),
            kernelAdminRoleExecutionDelay: uint32(vm.envUint("ADMIN_KERNEL_ROLE_EXECUTION_DELAY")),
            oracleQuoterAdminRoleAddress: vm.envAddress("ADMIN_ORACLE_QUOTER_ROLE_ADDRESS"),
            oracleQuoterAdminRoleExecutionDelay: uint32(vm.envUint("ADMIN_ORACLE_QUOTER_ROLE_EXECUTION_DELAY"))
        });
    }

    /// @notice Reads YDM-specific parameters from environment variables
    /// @param _ydmType The YDM type
    /// @return params Encoded YDM-specific parameters
    function _readYDMParamsFromEnv(YDMType _ydmType) internal view returns (bytes memory params) {
        if (_ydmType == YDMType.StaticCurve) {
            StaticCurveYDMParams memory ydmParams = StaticCurveYDMParams({
                jtYieldShareAtZeroUtilWAD: uint64(vm.envUint("YDM_JT_YIELD_SHARE_AT_ZERO_UTIL_WAD")),
                jtYieldShareAtTargetUtilWAD: uint64(vm.envUint("YDM_JT_YIELD_SHARE_AT_TARGET_UTIL_WAD")),
                jtYieldShareAtFullUtilWAD: uint64(vm.envUint("YDM_JT_YIELD_SHARE_AT_FULL_UTIL_WAD"))
            });
            params = abi.encode(ydmParams);
        } else if (_ydmType == YDMType.AdaptiveCurve) {
            AdaptiveCurveYDMParams memory ydmParams = AdaptiveCurveYDMParams({
                jtYieldShareAtTargetUtilWAD: uint64(vm.envUint("YDM_JT_YIELD_SHARE_AT_TARGET_UTIL_WAD")),
                jtYieldShareAtFullUtilWAD: uint64(vm.envUint("YDM_JT_YIELD_SHARE_AT_FULL_UTIL_WAD"))
            });
            params = abi.encode(ydmParams);
        } else {
            revert UnsupportedYDMType(_ydmType);
        }
    }

    /// @notice Deploys accountant implementation
    /// @return The deployed accountant implementation
    function _deployAccountantImpl() internal returns (RoycoAccountant) {
        bytes memory creationCode = type(RoycoAccountant).creationCode;

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(ACCOUNTANT_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("Accountant implementation already deployed at:", addr);
        } else {
            console2.log("Accountant implementation deployed at:", addr);
        }
        return RoycoAccountant(addr);
    }

    /// @notice Deploys ST tranche implementation
    /// @return The deployed ST tranche implementation
    function _deploySTTrancheImpl() internal returns (RoycoSeniorTranche) {
        bytes memory creationCode = type(RoycoSeniorTranche).creationCode;

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(ST_TRANCHE_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("ST tranche implementation already deployed at:", addr);
        } else {
            console2.log("ST tranche implementation deployed at:", addr);
        }
        return RoycoSeniorTranche(addr);
    }

    /// @notice Deploys JT tranche implementation
    /// @return The deployed JT tranche implementation
    function _deployJTTrancheImpl() internal returns (RoycoJuniorTranche) {
        bytes memory creationCode = type(RoycoJuniorTranche).creationCode;

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(JT_TRANCHE_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("JT tranche implementation already deployed at:", addr);
        } else {
            console2.log("JT tranche implementation deployed at:", addr);
        }
        return RoycoJuniorTranche(addr);
    }

    /// @notice Deploys YDM implementation based on YDM type
    /// @param _ydmType The YDM type to deploy
    /// @return ydm The deployed YDM contract
    function _deployYDM(YDMType _ydmType) internal returns (IYDM) {
        bytes memory creationCode;
        bytes32 salt;

        if (_ydmType == YDMType.StaticCurve) {
            creationCode = type(StaticCurveYDM).creationCode;
            salt = keccak256(abi.encodePacked(YDM_SALT, "STATIC_CURVE"));
        } else if (_ydmType == YDMType.AdaptiveCurve) {
            creationCode = type(AdaptiveCurveYDM).creationCode;
            salt = keccak256(abi.encodePacked(YDM_SALT, "ADAPTIVE_CURVE"));
        } else {
            revert UnsupportedYDMType(_ydmType);
        }

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(salt, creationCode, false);
        if (alreadyDeployed) {
            console2.log("YDM already deployed at:", addr);
        } else {
            console2.log("YDM deployed at:", addr);
        }
        return IYDM(addr);
    }

    /// @notice Deploys factory implementation
    /// @param _factoryAdmin The address of the factory admin
    /// @return The deployed factory implementation
    function _deployFactory(address _factoryAdmin) internal returns (RoycoFactory) {
        bytes memory creationCode = abi.encodePacked(type(RoycoFactory).creationCode, abi.encode(_factoryAdmin));

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(FACTORY_SALT_BASE, creationCode, false);
        if (alreadyDeployed) {
            console2.log("Factory already deployed at:", addr);
        } else {
            console2.log("Factory deployed at:", addr);
        }
        return RoycoFactory(addr);
    }

    /// @notice Deploys kernel implementation based on kernel type
    function _deployKernelImpl(
        KernelType _kernelType,
        bytes memory _kernelSpecificParams,
        address _expectedSeniorTrancheAddress,
        address _expectedJuniorTrancheAddress,
        address _seniorAsset,
        address _juniorAsset
    )
        internal
        returns (address)
    {
        IRoycoKernel.RoycoKernelConstructionParams memory constructionParams = IRoycoKernel.RoycoKernelConstructionParams({
            seniorTranche: _expectedSeniorTrancheAddress, stAsset: _seniorAsset, juniorTranche: _expectedJuniorTrancheAddress, jtAsset: _juniorAsset
        });

        if (_kernelType == KernelType.ERC4626_ST_AaveV3_JT_InKindAssets) {
            return address(_deployERC4626STAaveV3JTInKindAssetsKernelImpl(constructionParams, _kernelSpecificParams));
        } else if (_kernelType == KernelType.ERC4626_ST_ERC4626_JT_InKindAssets) {
            return address(_deployERC4626STERC4626JTInKindAssetsKernelImpl(constructionParams, _kernelSpecificParams));
        } else if (_kernelType == KernelType.ReUSD_ST_ReUSD_JT) {
            return address(_deployReUSDSTReUSDJTKernelImpl(constructionParams, _kernelSpecificParams));
        } else if (_kernelType == KernelType.YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter) {
            return address(_deployYieldBearingERC20STYieldBearingERC20JTIdenticalAssetsChainlinkOracleQuoterKernelImpl(constructionParams));
        } else if (_kernelType == KernelType.YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets) {
            return address(_deployYieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626AssetsKernelImpl(constructionParams));
        } else {
            revert UnsupportedKernelType(_kernelType);
        }
    }

    function _deployERC4626STAaveV3JTInKindAssetsKernelImpl(
        IRoycoKernel.RoycoKernelConstructionParams memory _constructionParams,
        bytes memory _params
    )
        internal
        returns (ERC4626_ST_AaveV3_JT_InKindAssets_Kernel)
    {
        ERC4626STAaveV3JTInKindAssetsKernelParams memory kernelParams = abi.decode(_params, (ERC4626STAaveV3JTInKindAssetsKernelParams));

        bytes memory creationCode = abi.encodePacked(
            type(ERC4626_ST_AaveV3_JT_InKindAssets_Kernel).creationCode, abi.encode(_constructionParams, kernelParams.stVault, kernelParams.aaveV3Pool)
        );

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(KERNEL_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("Kernel implementation already deployed at:", addr);
        } else {
            console2.log("Kernel implementation deployed at:", addr);
        }
        return ERC4626_ST_AaveV3_JT_InKindAssets_Kernel(addr);
    }

    function _deployERC4626STERC4626JTInKindAssetsKernelImpl(
        IRoycoKernel.RoycoKernelConstructionParams memory _constructionParams,
        bytes memory _params
    )
        internal
        returns (ERC4626_ST_ERC4626_JT_InKindAssets_Kernel)
    {
        ERC4626STERC4626JTInKindAssetsKernelParams memory kernelParams = abi.decode(_params, (ERC4626STERC4626JTInKindAssetsKernelParams));

        bytes memory creationCode = abi.encodePacked(
            type(ERC4626_ST_ERC4626_JT_InKindAssets_Kernel).creationCode, abi.encode(_constructionParams, kernelParams.stVault, kernelParams.jtVault)
        );

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(KERNEL_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("Kernel implementation already deployed at:", addr);
        } else {
            console2.log("Kernel implementation deployed at:", addr);
        }
        return ERC4626_ST_ERC4626_JT_InKindAssets_Kernel(addr);
    }

    function _deployReUSDSTReUSDJTKernelImpl(
        IRoycoKernel.RoycoKernelConstructionParams memory _constructionParams,
        bytes memory _params
    )
        internal
        returns (ReUSD_ST_ReUSD_JT_Kernel)
    {
        ReUSDSTReUSDJTKernelParams memory kernelParams = abi.decode(_params, (ReUSDSTReUSDJTKernelParams));

        bytes memory creationCode = abi.encodePacked(
            type(ReUSD_ST_ReUSD_JT_Kernel).creationCode,
            abi.encode(_constructionParams, kernelParams.reusd, kernelParams.reusdUsdQuoteToken, kernelParams.insuranceCapitalLayer)
        );

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(KERNEL_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("Kernel implementation already deployed at:", addr);
        } else {
            console2.log("Kernel implementation deployed at:", addr);
        }
        return ReUSD_ST_ReUSD_JT_Kernel(addr);
    }

    function _deployYieldBearingERC20STYieldBearingERC20JTIdenticalAssetsChainlinkOracleQuoterKernelImpl(
        IRoycoKernel.RoycoKernelConstructionParams memory _constructionParams
    )
        internal
        returns (YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel)
    {
        bytes memory creationCode = abi.encodePacked(
            type(YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel).creationCode, abi.encode(_constructionParams)
        );

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(KERNEL_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("Kernel implementation already deployed at:", addr);
        } else {
            console2.log("Kernel implementation deployed at:", addr);
        }
        return YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel(addr);
    }

    function _deployYieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626AssetsKernelImpl(
        IRoycoKernel.RoycoKernelConstructionParams memory _constructionParams
    )
        internal
        returns (YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel)
    {
        bytes memory creationCode = abi.encodePacked(
            type(YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel).creationCode, abi.encode(_constructionParams)
        );

        (address addr, bool alreadyDeployed) = deployWithSanityChecks(KERNEL_IMPL_SALT, creationCode, false);
        if (alreadyDeployed) {
            console2.log("Kernel implementation already deployed at:", addr);
        } else {
            console2.log("Kernel implementation deployed at:", addr);
        }
        return YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel(addr);
    }

    function _buildKernelInitializationData(
        KernelType _kernelType,
        bytes memory _kernelSpecificParams,
        address _expectedAccountantAddress,
        address _factoryAddress,
        DeploymentParams memory _params
    )
        internal
        pure
        returns (bytes memory)
    {
        RoycoKernelInitParams memory kernelParams = RoycoKernelInitParams({
            initialAuthority: _factoryAddress,
            accountant: _expectedAccountantAddress,
            protocolFeeRecipient: _params.protocolFeeRecipient,
            jtRedemptionDelayInSeconds: _params.jtRedemptionDelayInSeconds
        });

        if (_kernelType == KernelType.ERC4626_ST_AaveV3_JT_InKindAssets) {
            return abi.encodeCall(ERC4626_ST_AaveV3_JT_InKindAssets_Kernel.initialize, (kernelParams));
        } else if (_kernelType == KernelType.ERC4626_ST_ERC4626_JT_InKindAssets) {
            return abi.encodeCall(ERC4626_ST_ERC4626_JT_InKindAssets_Kernel.initialize, (kernelParams));
        } else if (_kernelType == KernelType.ReUSD_ST_ReUSD_JT) {
            return abi.encodeCall(ReUSD_ST_ReUSD_JT_Kernel.initialize, (kernelParams));
        } else if (_kernelType == KernelType.YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter) {
            YieldBearingERC20STYieldBearingERC20JTIdenticalAssetsChainlinkOracleQuoterKernelParams memory kernelParams2 =
                abi.decode(_kernelSpecificParams, (YieldBearingERC20STYieldBearingERC20JTIdenticalAssetsChainlinkOracleQuoterKernelParams));
            return abi.encodeCall(
                YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel.initialize,
                (
                    kernelParams,
                    kernelParams2.trancheAssetToReferenceAssetOracle,
                    kernelParams2.stalenessThresholdSeconds,
                    kernelParams2.initialConversionRateWAD
                )
            );
        } else if (_kernelType == KernelType.YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets) {
            YieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626AssetsKernelParams memory kernelParams2 =
                abi.decode(_kernelSpecificParams, (YieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626AssetsKernelParams));
            return abi.encodeCall(
                YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel.initialize, (kernelParams, kernelParams2.initialConversionRateWAD)
            );
        } else {
            revert UnsupportedKernelType(_kernelType);
        }
    }

    /// @notice Builds YDM initialization data based on YDM type
    /// @param _ydmType The YDM type
    /// @param _ydmSpecificParams Encoded YDM-specific parameters
    /// @return ydmInitializationData The encoded YDM initialization data
    function _buildYDMInitializationData(YDMType _ydmType, bytes memory _ydmSpecificParams) internal pure returns (bytes memory ydmInitializationData) {
        if (_ydmType == YDMType.StaticCurve) {
            StaticCurveYDMParams memory ydmParams = abi.decode(_ydmSpecificParams, (StaticCurveYDMParams));
            ydmInitializationData = abi.encodeCall(
                StaticCurveYDM.initializeYDMForMarket,
                (ydmParams.jtYieldShareAtZeroUtilWAD, ydmParams.jtYieldShareAtTargetUtilWAD, ydmParams.jtYieldShareAtFullUtilWAD)
            );
        } else if (_ydmType == YDMType.AdaptiveCurve) {
            AdaptiveCurveYDMParams memory ydmParams = abi.decode(_ydmSpecificParams, (AdaptiveCurveYDMParams));
            ydmInitializationData =
                abi.encodeCall(AdaptiveCurveYDM.initializeYDMForMarket, (ydmParams.jtYieldShareAtTargetUtilWAD, ydmParams.jtYieldShareAtFullUtilWAD));
        } else {
            revert UnsupportedYDMType(_ydmType);
        }
    }

    function _buildAccountantInitializationData(
        address _expectedKernelAddress,
        address _ydmAddress,
        address _factoryAddress,
        DeploymentParams memory _params
    )
        internal
        pure
        returns (bytes memory)
    {
        IRoycoAccountant.RoycoAccountantInitParams memory accountantParams = IRoycoAccountant.RoycoAccountantInitParams({
            kernel: _expectedKernelAddress,
            stProtocolFeeWAD: _params.stProtocolFeeWAD,
            jtProtocolFeeWAD: _params.jtProtocolFeeWAD,
            coverageWAD: _params.coverageWAD,
            betaWAD: _params.betaWAD,
            lltvWAD: _params.lltvWAD,
            ydm: _ydmAddress,
            ydmInitializationData: _buildYDMInitializationData(_params.ydmType, _params.ydmSpecificParams),
            fixedTermDurationSeconds: _params.fixedTermDurationSeconds
        });

        return abi.encodeCall(RoycoAccountant.initialize, (accountantParams, _factoryAddress));
    }

    function _buildSeniorTrancheInitializationData(
        address _expectedKernelAddress,
        bytes32 _marketId,
        address _factoryAddress,
        DeploymentParams memory _params
    )
        internal
        pure
        returns (bytes memory)
    {
        TrancheDeploymentParams memory trancheParams =
            TrancheDeploymentParams({ name: _params.seniorTrancheName, symbol: _params.seniorTrancheSymbol, kernel: _expectedKernelAddress });

        return abi.encodeCall(RoycoSeniorTranche.initialize, (trancheParams, _params.seniorAsset, _factoryAddress, _marketId));
    }

    function _buildJuniorTrancheInitializationData(
        address _expectedKernelAddress,
        bytes32 _marketId,
        address _factoryAddress,
        DeploymentParams memory _params
    )
        internal
        pure
        returns (bytes memory)
    {
        TrancheDeploymentParams memory trancheParams =
            TrancheDeploymentParams({ name: _params.juniorTrancheName, symbol: _params.juniorTrancheSymbol, kernel: _expectedKernelAddress });

        return abi.encodeCall(RoycoJuniorTranche.initialize, (trancheParams, _params.juniorAsset, _factoryAddress, _marketId));
    }

    function _transferFactoryOwnership(RoycoFactory _factory, address _newAdmin) internal {
        // Check if new admin is already admin
        (bool isNewAdminAdmin,) = IAccessManager(address(_factory)).hasRole(0, _newAdmin);
        if (isNewAdminAdmin) {
            console2.log("New admin already has ADMIN_ROLE, skipping transfer");
            return;
        }

        console2.log("Transferring factory ownership to:", _newAdmin);

        // Grant ADMIN_ROLE to new admin (execution delay = 0 for immediate effect)
        IAccessManager(address(_factory)).grantRole(0, _newAdmin, 0);

        console2.log("Factory ownership transferred successfully");
        console2.log("New factory admin:", _newAdmin);
    }
}
