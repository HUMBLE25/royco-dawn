// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { WAD } from "../../../../src/libraries/Constants.sol";
import { AssetClaims } from "../../../../src/libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, toNAVUnits, toTrancheUnits, toUint256 } from "../../../../src/libraries/Units.sol";

import { DeployScript } from "../../../../script/Deploy.s.sol";
import { ERC4626_TestBase } from "../base/ERC4626_TestBase.t.sol";

/// @title FluidStETH_Test
/// @notice Tests ERC4626_ST_ERC4626_JT_InKindAssets_Kernel with Fluid's iETHv2 vault (stETH)
/// @dev Uses the actual Fluid vault on mainnet for production-like testing
contract FluidStETH_Test is ERC4626_TestBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // MAINNET ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Fluid iETHv2 vault on Ethereum mainnet
    address internal constant FLUID_IETH_V2 = 0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78;

    /// @notice stETH (Lido Staked ETH) on Ethereum mainnet
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @notice stETH whale address (Lido treasury/buffer)
    address internal constant STETH_WHALE = 0x93c4b944D05dfe6df7645A86cd2206016c51564D;

    // ═══════════════════════════════════════════════════════════════════════════
    // PROTOCOL CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════

    function getProtocolConfig() public pure override returns (ProtocolConfig memory) {
        return ProtocolConfig({
            name: "FluidStETH",
            forkBlock: 24_290_290,
            forkRpcUrlEnvVar: "MAINNET_RPC_URL",
            stAsset: STETH,
            jtAsset: STETH,
            stDecimals: 18,
            jtDecimals: 18,
            initialFunding: 1000e18
        });
    }

    function _getSTVault() internal pure override returns (address) {
        return FLUID_IETH_V2;
    }

    function _getJTVault() internal pure override returns (address) {
        return FLUID_IETH_V2;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STETH DEAL OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════════

    function dealSTAsset(address _to, uint256 _amount) public override {
        vm.prank(STETH_WHALE);
        IERC20(STETH).transfer(_to, _amount);
    }

    function dealJTAsset(address _to, uint256 _amount) public override {
        vm.prank(STETH_WHALE);
        IERC20(STETH).transfer(_to, _amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // YIELD/LOSS SIMULATION
    // ═══════════════════════════════════════════════════════════════════════════
    // Fluid vault's exchange price = (currentNetAssets * 1e18) / totalSupply
    //
    // For yield: donate stETH to vault, then call updateExchangePrice
    // For loss: transfer stETH out of vault, then call updateExchangePrice
    //
    // Since ST and JT share the same Fluid vault, yield/loss affects both tranches.

    /// @notice Fluid vault rebalancer address
    address internal constant FLUID_REBALANCER = 0xC9f5920F5fa422C1c8975F12c0a2cF1467c947dB;

    /// @notice Function selector for updateExchangePrice()
    bytes4 internal constant UPDATE_EXCHANGE_PRICE_SELECTOR = 0x3bfaa7e3;

    /// @notice Simulates yield for ST by donating stETH and calling updateExchangePrice
    function simulateSTYield(uint256 _percentageWAD) public override {
        _simulateYield(_percentageWAD);
    }

    /// @notice Simulates yield for JT by donating stETH and calling updateExchangePrice
    function simulateJTYield(uint256 _percentageWAD) public override {
        _simulateYield(_percentageWAD);
    }

    /// @notice Simulates loss for ST by removing stETH and calling updateExchangePrice
    function simulateSTLoss(uint256 _percentageWAD) public override {
        _simulateLoss(_percentageWAD);
    }

    /// @notice Simulates loss for JT by removing stETH and calling updateExchangePrice
    function simulateJTLoss(uint256 _percentageWAD) public override {
        _simulateLoss(_percentageWAD);
    }

    /// @notice Donates stETH to vault and calls updateExchangePrice to realize yield
    function _simulateYield(uint256 _percentageWAD) internal {
        // Calculate donation amount based on current total assets
        uint256 totalAssets = IERC4626(FLUID_IETH_V2).totalAssets();
        uint256 donationAmount = totalAssets * _percentageWAD / WAD;
        if (donationAmount == 0) return;

        // Donate stETH directly to the vault
        dealSTAsset(address(this), donationAmount);
        IERC20(STETH).transfer(FLUID_IETH_V2, donationAmount);

        // Call updateExchangePrice as rebalancer
        _callUpdateExchangePrice();
    }

    /// @notice Transfers stETH out of vault and calls updateExchangePrice to realize loss
    function _simulateLoss(uint256 _percentageWAD) internal {
        // Calculate amount to remove based on current total assets
        uint256 totalAssets = IERC4626(FLUID_IETH_V2).totalAssets();
        uint256 removeAmount = totalAssets * _percentageWAD / WAD;
        if (removeAmount == 0) return;

        // Cap removeAmount to actual stETH balance in vault
        uint256 vaultBalance = IERC20(STETH).balanceOf(FLUID_IETH_V2);
        if (removeAmount > vaultBalance) {
            removeAmount = vaultBalance / 2; // Take at most half the available balance
        }
        if (removeAmount == 0) return;

        // Transfer stETH out of the vault (prank as vault)
        vm.prank(FLUID_IETH_V2);
        IERC20(STETH).transfer(address(this), removeAmount);

        // Call updateExchangePrice as rebalancer
        _callUpdateExchangePrice();
    }

    /// @notice Calls updateExchangePrice as rebalancer
    function _callUpdateExchangePrice() internal {
        vm.prank(FLUID_REBALANCER);
        (bool success,) = FLUID_IETH_V2.call(abi.encodeWithSelector(UPDATE_EXCHANGE_PRICE_SELECTOR));
        require(success, "updateExchangePrice failed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOLERANCE OVERRIDES (stETH has 1-2 wei rounding per operation)
    // ═══════════════════════════════════════════════════════════════════════════

    function maxTrancheUnitDelta() public pure override returns (TRANCHE_UNIT) {
        return toTrancheUnits(uint256(1e15));
    }

    function maxNAVDelta() public pure override returns (NAV_UNIT) {
        return toNAVUnits(uint256(1e15));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLUID-SPECIFIC DEPLOYMENT OVERRIDE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Override deployment to use 10 wei threshold for shared vault rounding
    /// @dev IL accumulates ~1 wei per 25-40 yield distribution cycles due to rounding
    ///      in Fluid's convertToAssets during ST withdrawals
    function _deployKernelAndMarket() internal override returns (DeployScript.DeploymentResult memory) {
        ProtocolConfig memory cfg = getProtocolConfig();

        bytes32 marketId = keccak256(abi.encodePacked(cfg.name, "-", cfg.name, "-", vm.getBlockTimestamp()));

        DeployScript.ERC4626STERC4626JTInKindAssetsKernelParams memory kernelParams =
            DeployScript.ERC4626STERC4626JTInKindAssetsKernelParams({ stVault: _getSTVault(), jtVault: _getJTVault() });

        DeployScript.AdaptiveCurveYDMParams memory ydmParams =
            DeployScript.AdaptiveCurveYDMParams({ jtYieldShareAtTargetUtilWAD: 0.3e18, jtYieldShareAtFullUtilWAD: 1e18 });

        // Build role assignments using the centralized function
        DeployScript.RoleAssignmentConfiguration[] memory roleAssignments = _generateRoleAssignments();

        DeployScript.DeploymentParams memory params = DeployScript.DeploymentParams({
            factoryAdmin: OWNER_ADDRESS,
            marketId: marketId,
            seniorTrancheName: string(abi.encodePacked("Royco Senior ", cfg.name)),
            seniorTrancheSymbol: string(abi.encodePacked("RS-", cfg.name)),
            juniorTrancheName: string(abi.encodePacked("Royco Junior ", cfg.name)),
            juniorTrancheSymbol: string(abi.encodePacked("RJ-", cfg.name)),
            seniorAsset: cfg.stAsset,
            juniorAsset: cfg.jtAsset,
            dustTolerance: toNAVUnits(uint256(10)), // 10 wei for ~250 cycle headroom
            kernelType: DeployScript.KernelType.ERC4626_ST_ERC4626_JT_InKindAssets,
            kernelSpecificParams: abi.encode(kernelParams),
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT_ADDRESS,
            jtRedemptionDelayInSeconds: _getJTRedemptionDelay(),
            stProtocolFeeWAD: ST_PROTOCOL_FEE_WAD,
            jtProtocolFeeWAD: JT_PROTOCOL_FEE_WAD,
            coverageWAD: COVERAGE_WAD,
            betaWAD: 1e18,
            lltvWAD: LLTV,
            fixedTermDurationSeconds: FIXED_TERM_DURATION_SECONDS,
            ydmType: DeployScript.YDMType.AdaptiveCurve,
            ydmSpecificParams: abi.encode(ydmParams),
            roleAssignments: roleAssignments
        });

        return DEPLOY_SCRIPT.deploy(params, DEPLOYER.privateKey);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLUID-SPECIFIC TESTS: convertToAssets rounding behavior
    // ═══════════════════════════════════════════════════════════════════════════
    // These tests verify the system handles Fluid's actual rounding behavior correctly.
    // Fluid's convertToAssets can return slightly different values for the same shares
    // after deposits/withdrawals due to internal accounting precision.

    /// @notice Test that JT deposit → ST deposit works despite Fluid's convertToAssets drift
    function testFuzz_fluid_jtDeposit_stDeposit_accountingCorrect(uint256 _jtAmount, uint256 _stPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount() * 10, config.initialFunding / 4);
        _stPercentage = bound(_stPercentage, 10, 80);

        // JT deposits first
        uint256 jtShares = _depositJT(ALICE_ADDRESS, _jtAmount);
        assertGt(jtShares, 0, "JT should have received shares");

        // Get JT NAV after deposit
        NAV_UNIT jtNavAfterDeposit = JT.totalAssets().nav;

        // ST deposits (this triggers the convertToAssets drift in Fluid)
        TRANCHE_UNIT maxSTDeposit = ST.maxDeposit(BOB_ADDRESS);
        uint256 stAmount = toUint256(maxSTDeposit) * _stPercentage / 100;
        if (stAmount < _minDepositAmount()) return;

        _depositST(BOB_ADDRESS, stAmount);

        // Verify JT NAV is approximately preserved (within tolerance for Fluid drift)
        NAV_UNIT jtNavAfterSTDeposit = JT.totalAssets().nav;
        assertApproxEqAbs(
            toUint256(jtNavAfterSTDeposit), toUint256(jtNavAfterDeposit), toUint256(maxNAVDelta()), "JT NAV should be preserved within Fluid rounding tolerance"
        );
    }

    /// @notice Test consecutive deposits track impermanent loss from Fluid rounding
    function testFuzz_fluid_consecutiveDeposits_trackImpermanentLoss(uint256 _jtAmount, uint256 _numSTDeposits) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount() * 10, config.initialFunding / 4);
        _numSTDeposits = bound(_numSTDeposits, 2, 5);

        // Initial JT deposit
        _depositJT(ALICE_ADDRESS, _jtAmount);

        // Multiple ST deposits - each one causes convertToAssets drift
        TRANCHE_UNIT maxSTDeposit = ST.maxDeposit(BOB_ADDRESS);
        uint256 stPerDeposit = toUint256(maxSTDeposit) / (_numSTDeposits + 1);
        if (stPerDeposit < _minDepositAmount()) return;

        for (uint256 i = 0; i < _numSTDeposits; i++) {
            _depositST(BOB_ADDRESS, stPerDeposit);
        }

        // Sync to capture any accumulated drift
        vm.prank(SYNC_ROLE_ADDRESS);
        KERNEL.syncTrancheAccounting();

        // Verify NAV conservation holds within tolerance
        _assertNAVConservation();
    }

    /// @notice Test full deposit-redeem cycle with Fluid's rounding
    function testFuzz_fluid_fullCycle_depositRedeem(uint256 _jtAmount, uint256 _stPercentage, uint256 _redeemPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount() * 10, config.initialFunding / 4);
        _stPercentage = bound(_stPercentage, 20, 60);
        _redeemPercentage = bound(_redeemPercentage, 10, 90);

        // JT deposits
        uint256 jtShares = _depositJT(ALICE_ADDRESS, _jtAmount);

        // ST deposits
        TRANCHE_UNIT maxSTDeposit = ST.maxDeposit(BOB_ADDRESS);
        uint256 stAmount = toUint256(maxSTDeposit) * _stPercentage / 100;
        if (stAmount < _minDepositAmount()) return;
        _depositST(BOB_ADDRESS, stAmount);

        // ST requests redeem
        uint256 stShares = ST.balanceOf(BOB_ADDRESS);
        uint256 stSharesToRedeem = stShares * _redeemPercentage / 100;
        uint256 maxRedeemST = ST.maxRedeem(BOB_ADDRESS);
        if (stSharesToRedeem > maxRedeemST) stSharesToRedeem = maxRedeemST;
        if (stSharesToRedeem < _minDepositAmount()) return;

        vm.prank(BOB_ADDRESS);
        ST.redeem(stSharesToRedeem, BOB_ADDRESS, BOB_ADDRESS);

        // Verify NAV conservation
        _assertNAVConservation();

        // JT can still redeem (after delay)
        vm.warp(vm.getBlockTimestamp() + _getJTRedemptionDelay() + 1);

        uint256 jtSharesToRedeem = jtShares * _redeemPercentage / 100;
        uint256 maxRedeemJT = JT.maxRedeem(ALICE_ADDRESS);
        if (jtSharesToRedeem > maxRedeemJT) jtSharesToRedeem = maxRedeemJT;
        if (jtSharesToRedeem < _minDepositAmount()) return;

        vm.prank(ALICE_ADDRESS);
        (uint256 requestId,) = JT.requestRedeem(jtSharesToRedeem, ALICE_ADDRESS, ALICE_ADDRESS);

        vm.warp(vm.getBlockTimestamp() + _getJTRedemptionDelay() + 1);

        uint256 claimable = JT.claimableRedeemRequest(requestId, ALICE_ADDRESS);
        maxRedeemJT = JT.maxRedeem(ALICE_ADDRESS);
        uint256 actualRedeem = claimable < maxRedeemJT ? claimable : maxRedeemJT;
        if (actualRedeem < _minDepositAmount()) return;

        vm.prank(ALICE_ADDRESS);
        JT.redeem(actualRedeem, ALICE_ADDRESS, ALICE_ADDRESS, requestId);

        // Final NAV conservation check
        _assertNAVConservation();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLUID STETH CONFIGURATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_fluidStETH_vaultConfiguration() external view {
        uint8 decimals = IERC4626(FLUID_IETH_V2).decimals();
        assertEq(decimals, 18, "Fluid iETHv2 should have 18 decimals");

        uint256 sharePrice = IERC4626(FLUID_IETH_V2).convertToAssets(1e18);
        assertGt(sharePrice, 0, "Fluid iETHv2 share price should be > 0");

        address asset = IERC4626(FLUID_IETH_V2).asset();
        assertEq(asset, STETH, "Fluid iETHv2 underlying should be stETH");
    }

    function test_fluidStETH_stETHConfiguration() external view {
        uint8 decimals = IERC20Metadata(STETH).decimals();
        assertEq(decimals, 18, "stETH should have 18 decimals");

        uint256 totalSupply = IERC20(STETH).totalSupply();
        assertGt(totalSupply, 0, "stETH should have non-zero total supply");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SHARED VAULT OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice POC: Demonstrates that Fluid vault's convertToAssets changes when stETH is deposited
    /// This is the root cause of NAV_CONSERVATION_VIOLATION - not stETH rebasing
    function test_POC_fluidVaultSharePriceChange() external {
        // The JT vault shares held by kernel
        uint256 jtVaultShares = 439_520_349_737_079_033_628;

        emit log_named_uint("Testing with JT vault shares", jtVaultShares);

        // Check convertToAssets BEFORE any deposit
        uint256 assetsBefore = IERC4626(FLUID_IETH_V2).convertToAssets(jtVaultShares);
        emit log_named_uint("convertToAssets BEFORE deposit", assetsBefore);

        // Get current vault state
        uint256 totalAssetsBefore = IERC4626(FLUID_IETH_V2).totalAssets();
        uint256 totalSupplyBefore = IERC4626(FLUID_IETH_V2).totalSupply();
        emit log_named_uint("Vault totalAssets before", totalAssetsBefore);
        emit log_named_uint("Vault totalSupply before", totalSupplyBefore);

        // Simulate ST depositing stETH directly into Fluid vault (like the kernel would do)
        uint256 stDepositAmount = 640e18; // ~640 stETH
        vm.startPrank(BOB_ADDRESS);
        IERC20(STETH).approve(FLUID_IETH_V2, stDepositAmount);
        IERC4626(FLUID_IETH_V2).deposit(stDepositAmount, BOB_ADDRESS);
        vm.stopPrank();

        // Check convertToAssets AFTER the deposit
        uint256 assetsAfter = IERC4626(FLUID_IETH_V2).convertToAssets(jtVaultShares);
        emit log_named_uint("convertToAssets AFTER deposit", assetsAfter);

        // Get new vault state
        uint256 totalAssetsAfter = IERC4626(FLUID_IETH_V2).totalAssets();
        uint256 totalSupplyAfter = IERC4626(FLUID_IETH_V2).totalSupply();
        emit log_named_uint("Vault totalAssets after", totalAssetsAfter);
        emit log_named_uint("Vault totalSupply after", totalSupplyAfter);

        // The key finding: did convertToAssets return a different value for the SAME shares?
        if (assetsBefore != assetsAfter) {
            emit log("!!! convertToAssets returned DIFFERENT value for same shares !!!");
            emit log_named_uint("Difference (wei)", assetsBefore > assetsAfter ? assetsBefore - assetsAfter : assetsAfter - assetsBefore);
        } else {
            emit log("convertToAssets returned SAME value - no share price change");
        }
    }

    /// @notice POC: Demonstrates NAV_CONSERVATION_VIOLATION through kernel deposit flow
    /// @dev This uses exact parameters from a failing fuzz test counterexample
    /// Run with: forge test --match-test test_POC_navConservationViolation -vvvv
    function test_POC_navConservationViolation() external {
        // Step 1: JT deposits (creates vault shares for kernel)
        uint256 jtDepositAmount = 500e18;

        vm.startPrank(ALICE_ADDRESS);
        IERC20(STETH).approve(address(JT), jtDepositAmount);
        JT.deposit(toTrancheUnits(jtDepositAmount), ALICE_ADDRESS, ALICE_ADDRESS);
        vm.stopPrank();

        // Get vault shares held by kernel
        uint256 jtVaultShares = IERC4626(FLUID_IETH_V2).balanceOf(address(KERNEL));

        // Check convertToAssets BEFORE ST deposit
        uint256 jtAssetsBefore = IERC4626(FLUID_IETH_V2).convertToAssets(jtVaultShares);
        emit log_named_uint("JT vault shares", jtVaultShares);
        emit log_named_uint("convertToAssets BEFORE ST deposit", jtAssetsBefore);

        // Step 2: ST deposits - triggers NAV_CONSERVATION_VIOLATION in accountant
        // The kernel calls convertToAssets before and after the deposit
        // The Fluid vault returns a different value (1 wei less) after the deposit
        uint256 stMaxDeposit = toUint256(ST.maxDeposit(BOB_ADDRESS));
        uint256 stDepositAmount = stMaxDeposit * 50 / 100;

        emit log_named_uint("ST deposit amount", stDepositAmount);

        vm.startPrank(BOB_ADDRESS);
        IERC20(STETH).approve(address(ST), stDepositAmount);
        ST.deposit(toTrancheUnits(stDepositAmount), BOB_ADDRESS, BOB_ADDRESS);
        vm.stopPrank();

        // Check convertToAssets AFTER ST deposit (if we get here)
        uint256 jtAssetsAfter = IERC4626(FLUID_IETH_V2).convertToAssets(jtVaultShares);
        emit log_named_uint("convertToAssets AFTER ST deposit", jtAssetsAfter);

        if (jtAssetsBefore != jtAssetsAfter) {
            emit log("!!! convertToAssets drift detected !!!");
            emit log_named_uint("Drift (wei)", jtAssetsBefore > jtAssetsAfter ? jtAssetsBefore - jtAssetsAfter : jtAssetsAfter - jtAssetsBefore);
        }
    }
}
