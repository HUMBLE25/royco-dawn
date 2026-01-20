// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { DeployScript } from "../../../../script/Deploy.s.sol";
import {
    YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626SharesAdminOracleQuoter_Kernel
} from "../../../../src/kernels/YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626SharesAdminOracleQuoter_Kernel.sol";
import { RAY, WAD } from "../../../../src/libraries/Constants.sol";
import { NAV_UNIT, TRANCHE_UNIT, toNAVUnits, toTrancheUnits, toUint256 } from "../../../../src/libraries/Units.sol";

import { AbstractKernelTestSuite } from "../../abstract/AbstractKernelTestSuite.t.sol";

/// @title YieldBearingERC4626_TestBase
/// @notice Base test contract for YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626SharesAdminOracleQuoter_Kernel
/// @dev Implements the test hooks for yield-bearing ERC4626 assets where ST and JT use identical assets
///
/// IMPORTANT: This kernel stores the `vaultAsset-to-NAV` conversion rate (e.g., NUSD->USD for sNUSD).
/// The actual tranche-to-NAV conversion combines:
///   1. ERC4626.convertToAssets(RAY) - share to vault asset rate
///   2. storedRate (in RAY) - vault asset to NAV rate
/// Result: trancheToNAV = shareToAsset * storedRate / RAY
abstract contract YieldBearingERC4626_TestBase is AbstractKernelTestSuite {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE FOR MOCKED SHARE PRICE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Tracks the mocked share price (in RAY precision)
    /// @dev When non-zero, this value is used to mock convertToAssets() calls
    uint256 internal mockedSharePriceRAY;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIGURATION (To be overridden by protocol-specific implementations)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns the initial vault-asset-to-NAV conversion rate (in RAY precision)
    /// @dev For stablecoins like sNUSD (where NUSD ≈ USD), this should be RAY (1e27)
    /// Override this for non-stablecoin vaults where the vault asset has a different NAV
    function _getInitialConversionRate() internal view virtual returns (uint256) {
        // Default: 1:1 conversion in RAY precision (for stablecoins)
        return RAY;
    }

    /// @notice Returns the JT redemption delay
    function _getJTRedemptionDelay() internal view virtual override returns (uint24) {
        return 7 days;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NAV MANIPULATION HOOKS IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Simulates yield for ST by increasing the conversion rate
    function simulateSTYield(uint256 _percentageWAD) public virtual override {
        _simulateYield(_percentageWAD);
    }

    /// @notice Simulates yield for JT by increasing the conversion rate
    /// @dev For identical assets, ST and JT share the same conversion rate
    function simulateJTYield(uint256 _percentageWAD) public virtual override {
        _simulateYield(_percentageWAD);
    }

    /// @notice Simulates loss for ST by decreasing the conversion rate
    function simulateSTLoss(uint256 _percentageWAD) public virtual override {
        _simulateLoss(_percentageWAD);
    }

    /// @notice Simulates loss for JT by decreasing the conversion rate
    /// @dev For identical assets, ST and JT share the same conversion rate
    function simulateJTLoss(uint256 _percentageWAD) public virtual override {
        _simulateLoss(_percentageWAD);
    }

    /// @notice Sets the conversion rate for ST (in RAY precision)
    function setSTConversionRate(uint256 _rateRAY) public virtual {
        _setConversionRate(_rateRAY);
    }

    /// @notice Sets the conversion rate for JT (in RAY precision)
    /// @dev For identical assets, this is the same as ST
    function setJTConversionRate(uint256 _rateRAY) public virtual {
        _setConversionRate(_rateRAY);
    }

    /// @notice Deals ST asset to an address
    function dealSTAsset(address _to, uint256 _amount) public virtual override {
        deal(config.stAsset, _to, _amount);
    }

    /// @notice Deals JT asset to an address
    function dealJTAsset(address _to, uint256 _amount) public virtual override {
        deal(config.jtAsset, _to, _amount);
    }

    /// @notice Returns max tranche unit delta for comparisons
    function maxTrancheUnitDelta() public view virtual override returns (TRANCHE_UNIT) {
        // Default: 1e12 tolerance (good for 18 decimal tokens)
        return toTrancheUnits(uint256(1e12));
    }

    /// @notice Returns max NAV delta for comparisons
    function maxNAVDelta() public view virtual override returns (NAV_UNIT) {
        // Default: 1e12 tolerance
        return toNAVUnits(uint256(1e12));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VAULT SHARE PRICE MANIPULATION (ERC4626 convertToAssets component)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Simulates vault share price yield by mocking convertToAssets()
    /// @param _percentageWAD The percentage increase in WAD (e.g., 0.05e18 = 5%)
    function simulateVaultSharePriceYield(uint256 _percentageWAD) public virtual {
        uint256 currentSharePrice = _getCurrentSharePriceRAY();
        uint256 newSharePrice = currentSharePrice * (WAD + _percentageWAD) / WAD;
        _mockConvertToAssets(newSharePrice);
    }

    /// @notice Simulates vault share price loss by mocking convertToAssets()
    /// @param _percentageWAD The percentage decrease in WAD (e.g., 0.05e18 = 5%)
    function simulateVaultSharePriceLoss(uint256 _percentageWAD) public virtual {
        uint256 currentSharePrice = _getCurrentSharePriceRAY();
        uint256 newSharePrice = currentSharePrice * (WAD - _percentageWAD) / WAD;
        _mockConvertToAssets(newSharePrice);
    }

    /// @notice Gets the current share price (either mocked or from the actual vault)
    /// @return The share price in RAY precision
    function _getCurrentSharePriceRAY() internal view returns (uint256) {
        if (mockedSharePriceRAY != 0) {
            return mockedSharePriceRAY;
        }
        // Get the actual share price from the vault
        return IERC4626(config.stAsset).convertToAssets(RAY);
    }

    /// @notice Mocks the convertToAssets function on the vault
    /// @param _newSharePriceRAY The new share price in RAY precision
    function _mockConvertToAssets(uint256 _newSharePriceRAY) internal {
        mockedSharePriceRAY = _newSharePriceRAY;

        // Mock convertToAssets(RAY) to return the new share price
        // The kernel calls: IERC4626(ST_ASSET).convertToAssets(RAY)
        vm.mockCall(config.stAsset, abi.encodeWithSelector(IERC4626.convertToAssets.selector, RAY), abi.encode(_newSharePriceRAY));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS (STORED CONVERSION RATE)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Simulates yield by increasing the conversion rate
    /// @param _percentageWAD The yield percentage in WAD (e.g., 0.05e18 = 5%)
    function _simulateYield(uint256 _percentageWAD) internal {
        uint256 currentRate = _getConversionRate();
        // Apply percentage increase: newRate = currentRate * (1 + percentage)
        uint256 newRate = currentRate * (WAD + _percentageWAD) / WAD;
        _setConversionRate(newRate);
    }

    /// @notice Simulates loss by decreasing the conversion rate
    /// @param _percentageWAD The loss percentage in WAD (e.g., 0.05e18 = 5%)
    function _simulateLoss(uint256 _percentageWAD) internal {
        uint256 currentRate = _getConversionRate();
        // Apply percentage decrease: newRate = currentRate * (1 - percentage)
        uint256 newRate = currentRate * (WAD - _percentageWAD) / WAD;
        _setConversionRate(newRate);
    }

    /// @notice Gets the current conversion rate using the kernel's getter (in RAY precision)
    function _getConversionRate() internal view returns (uint256) {
        return YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626SharesAdminOracleQuoter_Kernel(address(KERNEL)).getStoredConversionRateRAY();
    }

    /// @notice Sets the conversion rate using the kernel's setter (in RAY precision)
    /// @dev Requires ORACLE_QUOTER_ADMIN_ROLE, which is granted to OWNER_ADDRESS
    function _setConversionRate(uint256 _newRateRAY) internal {
        vm.prank(OWNER_ADDRESS);
        YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626SharesAdminOracleQuoter_Kernel(address(KERNEL)).setConversionRate(_newRateRAY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VAULT SHARE PRICE TESTS (ERC4626 convertToAssets component)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Tests that vault share price yield increases NAV
    /// @dev This tests the ERC4626.convertToAssets() component of the conversion rate
    function testFuzz_vaultSharePrice_yield_updatesNAV(uint256 _jtAmount, uint256 _yieldPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount(), config.initialFunding / 2);
        _yieldPercentage = bound(_yieldPercentage, 1, 50); // 1-50% yield

        _depositJT(ALICE_ADDRESS, _jtAmount);

        NAV_UNIT navBefore = JT.totalAssets().nav;

        // Simulate vault share price yield (mocks convertToAssets)
        simulateVaultSharePriceYield(_yieldPercentage * 1e16); // Convert to WAD

        // Trigger sync
        vm.prank(OWNER_ADDRESS);
        KERNEL.syncTrancheAccounting();

        NAV_UNIT navAfter = JT.totalAssets().nav;
        assertGt(navAfter, navBefore, "NAV should increase after vault share price yield");
    }

    /// @notice Tests that vault share price loss decreases NAV
    /// @dev This tests the ERC4626.convertToAssets() component of the conversion rate
    function testFuzz_vaultSharePrice_loss_updatesNAV(uint256 _jtAmount, uint256 _lossPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount(), config.initialFunding / 2);
        _lossPercentage = bound(_lossPercentage, 1, 30); // 1-30% loss

        _depositJT(ALICE_ADDRESS, _jtAmount);

        NAV_UNIT navBefore = JT.totalAssets().nav;

        // Simulate vault share price loss (mocks convertToAssets)
        simulateVaultSharePriceLoss(_lossPercentage * 1e16); // Convert to WAD

        // Trigger sync
        vm.prank(OWNER_ADDRESS);
        KERNEL.syncTrancheAccounting();

        NAV_UNIT navAfter = JT.totalAssets().nav;
        assertLt(navAfter, navBefore, "NAV should decrease after vault share price loss");
    }

    /// @notice Tests that vault share price yield with ST deposits distributes correctly
    function testFuzz_vaultSharePrice_yield_distributesToJT(uint256 _jtAmount, uint256 _stPercentage, uint256 _yieldPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount(), config.initialFunding / 2);
        _stPercentage = bound(_stPercentage, 10, 50);
        _yieldPercentage = bound(_yieldPercentage, 1, 20);

        _depositJT(ALICE_ADDRESS, _jtAmount);

        TRANCHE_UNIT maxSTDeposit = ST.maxDeposit(BOB_ADDRESS);
        uint256 stAmount = toUint256(maxSTDeposit) * _stPercentage / 100;

        if (stAmount < _minDepositAmount()) return;

        _depositST(BOB_ADDRESS, stAmount);

        NAV_UNIT jtNavBefore = JT.totalAssets().nav;

        // Simulate vault share price yield
        simulateVaultSharePriceYield(_yieldPercentage * 1e16);

        // Warp time for yield distribution
        vm.warp(vm.getBlockTimestamp() + 1 days);

        // Trigger sync
        vm.prank(OWNER_ADDRESS);
        KERNEL.syncTrancheAccounting();

        NAV_UNIT jtNavAfter = JT.totalAssets().nav;

        // JT should receive portion of yield based on YDM
        assertGe(jtNavAfter, jtNavBefore, "JT NAV should increase or stay same from vault share price yield");
    }

    /// @notice Tests NAV conservation after vault share price changes
    function testFuzz_vaultSharePrice_NAVConservation(uint256 _jtAmount, uint256 _yieldPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount(), config.initialFunding / 2);
        _yieldPercentage = bound(_yieldPercentage, 1, 30);

        _depositJT(ALICE_ADDRESS, _jtAmount);

        // Simulate vault share price yield
        simulateVaultSharePriceYield(_yieldPercentage * 1e16);

        vm.prank(OWNER_ADDRESS);
        KERNEL.syncTrancheAccounting();

        _assertNAVConservation();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploys the YieldBearingERC4626 kernel and market
    function _deployKernelAndMarket() internal override returns (DeployScript.DeploymentResult memory) {
        ProtocolConfig memory cfg = getProtocolConfig();

        bytes32 marketId = keccak256(abi.encodePacked(cfg.name, "-", cfg.name, "-", vm.getBlockTimestamp()));

        // Get initial conversion rate (vault asset to NAV, in RAY precision)
        uint256 initialConversionRate = _getInitialConversionRate();

        DeployScript.YieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626SharesAdminOracleQuoterKernelParams memory kernelParams =
            DeployScript.YieldBearingERC4626STYieldBearingERC4626JTIdenticalERC4626SharesAdminOracleQuoterKernelParams({
                initialConversionRateWAD: initialConversionRate
            });

        DeployScript.AdaptiveCurveYDMParams memory ydmParams = DeployScript.AdaptiveCurveYDMParams({
            jtYieldShareAtTargetUtilWAD: 0.3e18, // 30% at target utilization
            jtYieldShareAtFullUtilWAD: 1e18 // 100% at 100% utilization
        });

        DeployScript.DeploymentParams memory params = DeployScript.DeploymentParams({
            factoryAdmin: address(DEPLOY_SCRIPT),
            factoryOwnerAddress: OWNER_ADDRESS,
            marketId: marketId,
            seniorTrancheName: string(abi.encodePacked("Royco Senior ", cfg.name)),
            seniorTrancheSymbol: string(abi.encodePacked("RS-", cfg.name)),
            juniorTrancheName: string(abi.encodePacked("Royco Junior ", cfg.name)),
            juniorTrancheSymbol: string(abi.encodePacked("RJ-", cfg.name)),
            seniorAsset: cfg.stAsset,
            juniorAsset: cfg.jtAsset,
            kernelType: DeployScript.KernelType.YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626SharesAdminOracleQuoter,
            kernelSpecificParams: abi.encode(kernelParams),
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT_ADDRESS,
            jtRedemptionDelayInSeconds: _getJTRedemptionDelay(),
            stProtocolFeeWAD: ST_PROTOCOL_FEE_WAD,
            jtProtocolFeeWAD: JT_PROTOCOL_FEE_WAD,
            coverageWAD: COVERAGE_WAD,
            betaWAD: 1e18, // Beta = 1 for identical assets
            lltvWAD: LLTV,
            fixedTermDurationSeconds: FIXED_TERM_DURATION_SECONDS,
            ydmType: DeployScript.YDMType.AdaptiveCurve,
            ydmSpecificParams: abi.encode(ydmParams),
            pauserAddress: PAUSER_ADDRESS,
            pauserExecutionDelay: 0,
            upgraderAddress: UPGRADER_ADDRESS,
            upgraderExecutionDelay: 0,
            lpRoleAddress: OWNER_ADDRESS,
            lpRoleExecutionDelay: 0,
            syncRoleAddress: OWNER_ADDRESS,
            syncRoleExecutionDelay: 0,
            kernelAdminRoleAddress: OWNER_ADDRESS,
            kernelAdminRoleExecutionDelay: 0,
            oracleQuoterAdminRoleAddress: OWNER_ADDRESS,
            oracleQuoterAdminRoleExecutionDelay: 0
        });

        return DEPLOY_SCRIPT.deploy(params);
    }
}
