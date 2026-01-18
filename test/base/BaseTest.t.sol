// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { Vm } from "../../lib/forge-std/src/Vm.sol";
import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { DeployScript } from "../../script/Deploy.s.sol";
import { RoycoFactory } from "../../src/RoycoFactory.sol";
import { RoycoAccountant } from "../../src/accountant/RoycoAccountant.sol";
import { RoycoRoles } from "../../src/auth/RoycoRoles.sol";
import { IRoycoAccountant } from "../../src/interfaces/IRoycoAccountant.sol";
import { IYDM } from "../../src/interfaces/IYDM.sol";
import { IRoycoKernel } from "../../src/interfaces/kernel/IRoycoKernel.sol";
import { IRoycoVaultTranche } from "../../src/interfaces/tranche/IRoycoVaultTranche.sol";
import { AssetClaims, MarketState, TrancheType } from "../../src/libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, toUint256 } from "../../src/libraries/Units.sol";
import { RoycoJT } from "../../src/tranches/RoycoJT.sol";
import { RoycoST } from "../../src/tranches/RoycoST.sol";
import { Assertions } from "./Assertions.t.sol";

abstract contract BaseTest is Test, RoycoRoles, Assertions {
    uint256 internal constant BPS = 0.0001e18;

    struct TrancheState {
        NAV_UNIT rawNAV;
        NAV_UNIT effectiveNAV;
        TRANCHE_UNIT stAssetsClaim;
        TRANCHE_UNIT jtAssetsClaim;
        NAV_UNIT protocolFeeValue;
        uint256 totalShares;
    }

    // -----------------------------------------
    // Test Wallets
    // -----------------------------------------
    Vm.Wallet internal OWNER;
    address internal OWNER_ADDRESS;

    Vm.Wallet internal PAUSER;
    address internal PAUSER_ADDRESS;

    Vm.Wallet internal UPGRADER;
    address internal UPGRADER_ADDRESS;

    Vm.Wallet internal PROTOCOL_FEE_RECIPIENT;
    address internal PROTOCOL_FEE_RECIPIENT_ADDRESS;

    Vm.Wallet internal ALICE;
    Vm.Wallet internal BOB;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal DAN;

    address internal ALICE_ADDRESS;
    address internal BOB_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address internal DAN_ADDRESS;

    address[] internal providers;

    // -----------------------------------------
    // Assets
    // -----------------------------------------

    ERC20Mock internal MOCK_USDC;
    ERC20Mock internal MOCK_USDT;
    ERC20Mock internal MOCK_DAI;
    address[] internal ASSETS;

    // -----------------------------------------
    // Royco Deployments
    // -----------------------------------------

    // Deploy Script
    DeployScript internal DEPLOY_SCRIPT;

    // Deployments
    RoycoFactory internal FACTORY;
    IYDM internal YDM;
    RoycoST public ST_IMPL;
    RoycoJT internal JT_IMPL;
    RoycoAccountant internal ACCOUNTANT_IMPL;
    address internal KERNEL_IMPL;
    IRoycoVaultTranche internal ST;
    IRoycoVaultTranche internal JT;
    IRoycoKernel internal KERNEL;
    IRoycoAccountant internal ACCOUNTANT;
    bytes32 internal MARKET_ID;

    // -----------------------------------------
    // Royco Deployments Parameters
    // -----------------------------------------

    uint256 internal SEED_AMOUNT;
    string internal SENIOR_TRANCHE_NAME = "Royco Senior Tranche";
    string internal SENIOR_TRANCHE_SYMBOL = "RST";
    string internal JUNIOR_TRANCHE_NAME = "Royco Junior Tranche";
    string internal JUNIOR_TRANCHE_SYMBOL = "RJT";
    uint64 internal COVERAGE_WAD = 0.2e18; // 20% coverage
    uint96 internal BETA_WAD = 0; // Different opportunities
    uint64 internal ST_PROTOCOL_FEE_WAD = 0.1e18; // 10% protocol fee
    uint64 internal JT_PROTOCOL_FEE_WAD = 0.1e18; // 10% protocol fee
    uint64 internal LLTV = 0.97e18; // 95% LLTV
    uint24 internal FIXED_TERM_DURATION_SECONDS = 2 weeks; // 2 weeks in seconds

    /// -----------------------------------------
    /// Mainnet Fork Addresses
    /// -----------------------------------------
    uint256 internal forkId;
    address internal constant ETHEREUM_MAINNET_USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant ETHEREUM_MAINNET_AAVE_V3_POOL_ADDRESS = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    mapping(uint256 chainId => mapping(address asset => address aTokenAddress)) internal aTokenAddresses;

    constructor() {
        aTokenAddresses[1][ETHEREUM_MAINNET_USDC_ADDRESS] = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    }

    modifier prankModifier(address _pranker) {
        vm.startPrank(_pranker);
        _;
        vm.stopPrank();
    }

    function _setUpRoyco() internal virtual {
        _setupFork();
        _setupWallets();

        // Deploy the deploy script
        DEPLOY_SCRIPT = new DeployScript();
    }

    function _setupFork() internal {
        (uint256 forkBlock, string memory forkRpcUrl) = _forkConfiguration();
        if (bytes(forkRpcUrl).length > 0) {
            require(forkBlock != 0, "Fork block is required");
            vm.createSelectFork(forkRpcUrl, forkBlock);
        }
    }

    function _setupAssets(uint256 _seedAmount) internal {
        MOCK_USDC = new ERC20Mock();
        MOCK_USDC.mint(OWNER_ADDRESS, _seedAmount * (10 ** 18));
        MOCK_USDC.mint(ALICE_ADDRESS, _seedAmount * (10 ** 18));
        MOCK_USDC.mint(BOB_ADDRESS, _seedAmount * (10 ** 18));
        ASSETS.push(address(MOCK_USDC));

        MOCK_USDT = new ERC20Mock();
        MOCK_USDT.mint(OWNER_ADDRESS, _seedAmount * (10 ** 18));
        MOCK_USDT.mint(ALICE_ADDRESS, _seedAmount * (10 ** 18));
        MOCK_USDT.mint(BOB_ADDRESS, _seedAmount * (10 ** 18));
        ASSETS.push(address(MOCK_USDT));

        MOCK_DAI = new ERC20Mock();
        MOCK_DAI.mint(OWNER_ADDRESS, _seedAmount * (10 ** 18));
        MOCK_DAI.mint(ALICE_ADDRESS, _seedAmount * (10 ** 18));
        MOCK_DAI.mint(BOB_ADDRESS, _seedAmount * (10 ** 18));
        ASSETS.push(address(MOCK_DAI));
    }

    function _setupWallets() internal {
        OWNER = _initWallet("OWNER", 1000 ether);
        PAUSER = _initWallet("PAUSER", 1000 ether);
        UPGRADER = _initWallet("UPGRADER", 1000 ether);
        PROTOCOL_FEE_RECIPIENT = _initWallet("PROTOCOL_FEE_RECIPIENT", 1000 ether);

        OWNER_ADDRESS = OWNER.addr;
        PAUSER_ADDRESS = PAUSER.addr;
        PROTOCOL_FEE_RECIPIENT_ADDRESS = PROTOCOL_FEE_RECIPIENT.addr;
        UPGRADER_ADDRESS = UPGRADER.addr;
    }

    function _setupProviders() internal {
        // Init wallets with 1000 ETH each
        ALICE = _generateProvider("ALICE");
        BOB = _generateProvider("BOB");
        CHARLIE = _generateProvider("CHARLIE");
        DAN = _generateProvider("DAN");

        // Set addresses
        ALICE_ADDRESS = ALICE.addr;
        BOB_ADDRESS = BOB.addr;
        CHARLIE_ADDRESS = CHARLIE.addr;
        DAN_ADDRESS = DAN.addr;

        providers.push(ALICE_ADDRESS);
        providers.push(BOB_ADDRESS);
        providers.push(CHARLIE_ADDRESS);
        providers.push(DAN_ADDRESS);
    }

    function _setDeployedMarket(DeployScript.DeploymentResult memory _deploymentResult) internal {
        ST_IMPL = _deploymentResult.stTrancheImplementation;
        vm.label(address(ST_IMPL), "STImpl");

        JT_IMPL = _deploymentResult.jtTrancheImplementation;
        vm.label(address(JT_IMPL), "JTImpl");

        ACCOUNTANT_IMPL = _deploymentResult.accountantImplementation;
        vm.label(address(ACCOUNTANT_IMPL), "AccountantImpl");

        KERNEL_IMPL = _deploymentResult.kernelImplementation;
        vm.label(address(KERNEL_IMPL), "KernelImpl");

        YDM = _deploymentResult.ydm;
        vm.label(address(YDM), "YDM");

        ST = _deploymentResult.seniorTranche;
        vm.label(address(ST), "ST");

        JT = _deploymentResult.juniorTranche;
        vm.label(address(JT), "JT");

        ACCOUNTANT = _deploymentResult.accountant;
        vm.label(address(ACCOUNTANT), "Accountant");

        KERNEL = _deploymentResult.kernel;
        vm.label(address(KERNEL), "Kernel");

        FACTORY = _deploymentResult.factory;
        vm.label(address(FACTORY), "Factory");

        MARKET_ID = _deploymentResult.marketId;
    }

    function _initWallet(string memory _name, uint256 _amount) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = vm.createWallet(_name);
        vm.label(wallet.addr, _name);
        vm.deal(wallet.addr, _amount);
        return wallet;
    }

    /// @notice Generates a provider address
    /// @param _name The name of the provider
    /// @return provider The provider address
    function _generateProvider(string memory _name) internal virtual prankModifier(OWNER_ADDRESS) returns (Vm.Wallet memory provider) {
        // Generate a unique wallet
        provider = _initWallet(_name, 10_000_000e6);

        // Grant Permissions
        FACTORY.grantRole(RoycoRoles.DEPOSIT_ROLE, provider.addr, 0);
        FACTORY.grantRole(RoycoRoles.REDEEM_ROLE, provider.addr, 0);
        FACTORY.grantRole(RoycoRoles.CANCEL_DEPOSIT_ROLE, provider.addr, 0);
        FACTORY.grantRole(RoycoRoles.CANCEL_REDEEM_ROLE, provider.addr, 0);

        return provider;
    }

    /// @notice Generates a provider address
    /// @param index The index of the provider
    /// @return provider The provider address
    function _generateProvider(uint256 index) internal virtual prankModifier(OWNER_ADDRESS) returns (Vm.Wallet memory provider) {
        // Generate a unique wallet
        string memory providerName = string(abi.encodePacked("PROVIDER", vm.toString(index)));
        provider = _initWallet(providerName, 10_000_000e6);

        // Grant Permissions
        FACTORY.grantRole(RoycoRoles.DEPOSIT_ROLE, provider.addr, 0);
        FACTORY.grantRole(RoycoRoles.REDEEM_ROLE, provider.addr, 0);

        return provider;
    }

    /// @notice Verifies the preview NAVs of the senior and junior tranches
    /// @param _stState The state of the senior tranche
    /// @param _jtState The state of the junior tranche
    function _verifyPreviewNAVs(
        TrancheState memory _stState,
        TrancheState memory _jtState,
        TRANCHE_UNIT _maxAbsDeltaTrancheUnits,
        NAV_UNIT _maxAbsDeltaNAV
    )
        internal
        view
    {
        assertTrue(address(ST) != address(0), "Senior tranche is not deployed");
        assertTrue(address(JT) != address(0), "Junior tranche is not deployed");

        assertApproxEqAbs(ST.getRawNAV(), _stState.rawNAV, toUint256(_maxAbsDeltaNAV), "ST raw NAV mismatch");
        AssetClaims memory stClaims = ST.totalAssets();
        assertApproxEqAbs(stClaims.nav, _stState.effectiveNAV, toUint256(_maxAbsDeltaNAV), "ST effective NAV mismatch");
        assertApproxEqAbs(stClaims.stAssets, _stState.stAssetsClaim, toUint256(_maxAbsDeltaTrancheUnits), "ST st assets claim mismatch");
        assertApproxEqAbs(stClaims.jtAssets, _stState.jtAssetsClaim, toUint256(_maxAbsDeltaTrancheUnits), "ST jt assets claim mismatch");

        assertApproxEqAbs(JT.getRawNAV(), _jtState.rawNAV, toUint256(_maxAbsDeltaNAV), "JT raw NAV mismatch");
        AssetClaims memory jtClaims = JT.totalAssets();
        assertApproxEqAbs(jtClaims.nav, _jtState.effectiveNAV, toUint256(_maxAbsDeltaNAV), "JT effective NAV mismatch");
        assertApproxEqAbs(jtClaims.stAssets, _jtState.stAssetsClaim, toUint256(_maxAbsDeltaTrancheUnits), "JT st assets claim mismatch");
        assertApproxEqAbs(jtClaims.jtAssets, _jtState.jtAssetsClaim, toUint256(_maxAbsDeltaTrancheUnits), "JT jt assets claim mismatch");
    }

    /// @notice Verifies the fee taken by the senior and junior tranches
    /// @param _stState The state of the senior tranche
    /// @param _jtState The state of the junior tranche
    /// @param _feeRecipient The address of the fee recipient
    function _verifyFeeTaken(TrancheState storage _stState, TrancheState storage _jtState, address _feeRecipient) internal view {
        uint256 seniorFeeShares = ST.balanceOf(_feeRecipient);
        NAV_UNIT seniorFeeSharesValue = ST.convertToAssets(seniorFeeShares).nav;
        assertEq(seniorFeeSharesValue, _stState.protocolFeeValue, "ST protocol fee value mismatch");

        uint256 juniorFeeShares = JT.balanceOf(_feeRecipient);
        NAV_UNIT juniorFeeSharesValue = JT.convertToAssets(juniorFeeShares).nav;
        assertEq(juniorFeeSharesValue, _jtState.protocolFeeValue, "JT protocol fee value mismatch");
    }

    /// @notice Updates the state of the senior and junior tranches on a deposit
    /// @param _trancheState The state of the tranche
    /// @param _assets The amount of ASSETS deposited
    /// @param _assetsValue The value of the ASSETS deposited
    /// @param _shares The amount of shares deposited
    /// @param _trancheType The type of tranche
    function _updateOnDeposit(
        TrancheState storage _trancheState,
        TRANCHE_UNIT _assets,
        NAV_UNIT _assetsValue,
        uint256 _shares,
        TrancheType _trancheType
    )
        internal
    {
        _trancheState.rawNAV = _trancheState.rawNAV + _assetsValue;
        _trancheState.effectiveNAV = _trancheState.effectiveNAV + _assetsValue;
        if (_trancheType == TrancheType.SENIOR) {
            _trancheState.stAssetsClaim = _trancheState.stAssetsClaim + _assets;
        } else {
            _trancheState.jtAssetsClaim = _trancheState.jtAssetsClaim + _assets;
        }
        _trancheState.totalShares += _shares;
    }

    /// @notice Updates the state of the senior and junior tranches on a withdrawal
    /// @param _trancheState The state of the tranche
    /// @param _stAssetsWithdrawn The amount of ST assets withdrawn
    /// @param _jtAssetsWithdrawn The amount of JT assets withdrawn
    /// @param _totalAssetsValueWithdrawn The value of the ASSETS withdrawn
    /// @param _shares The amount of shares withdrawn
    function _updateOnWithdraw(
        TrancheState storage _trancheState,
        TRANCHE_UNIT _stAssetsWithdrawn,
        TRANCHE_UNIT _jtAssetsWithdrawn,
        NAV_UNIT _totalAssetsValueWithdrawn,
        uint256 _shares
    )
        internal
    {
        _trancheState.rawNAV = _trancheState.rawNAV - _totalAssetsValueWithdrawn;
        _trancheState.effectiveNAV = _trancheState.effectiveNAV - _totalAssetsValueWithdrawn;
        _trancheState.stAssetsClaim = _trancheState.stAssetsClaim - _stAssetsWithdrawn;
        _trancheState.jtAssetsClaim = _trancheState.jtAssetsClaim - _jtAssetsWithdrawn;
        _trancheState.totalShares = _trancheState.totalShares - _shares;
    }

    /// @notice Converts the specified assets denominated in JT's tranche units to the kernel's NAV units
    /// @param _assets The assets denominated in JT's tranche units to convert to the kernel's NAV units
    /// @return value The specified assets denominated in JT's tranche units converted to the kernel's NAV units
    function _toJTValue(TRANCHE_UNIT _assets) internal view returns (NAV_UNIT) {
        return KERNEL.jtConvertTrancheUnitsToNAVUnits(_assets);
    }

    /// @notice Converts the specified assets denominated in ST's tranche units to the kernel's NAV units
    /// @param _assets The assets denominated in ST's tranche units to convert to the kernel's NAV units
    /// @return value The specified assets denominated in ST's tranche units converted to the kernel's NAV units
    function _toSTValue(TRANCHE_UNIT _assets) internal view returns (NAV_UNIT) {
        return KERNEL.stConvertTrancheUnitsToNAVUnits(_assets);
    }

    /// @notice Deploys a KERNEL using ERC1967 proxy
    /// @param _kernelImplementation The implementation address
    /// @param _kernelInitData The initialization data
    /// @return KERNELProxy The deployed proxy address
    function _deployKernel(address _kernelImplementation, bytes memory _kernelInitData) internal returns (address KERNELProxy) {
        KERNELProxy = address(new ERC1967Proxy(_kernelImplementation, _kernelInitData));
    }

    /// @notice Returns the fork configuration
    /// @return forkBlock The fork block
    /// @return forkRpcUrl The fork RPC URL
    function _forkConfiguration() internal virtual returns (uint256 forkBlock, string memory forkRpcUrl) {
        return (0, "");
    }
}
