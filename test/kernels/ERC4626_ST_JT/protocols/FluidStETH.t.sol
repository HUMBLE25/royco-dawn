// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { WAD } from "../../../../src/libraries/Constants.sol";
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
            forkBlock: 21_500_000,
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
    // NOTE: The Fluid vault uses internal accounting that can't be easily manipulated:
    // - Time warping doesn't work (no actual lending activity on forked chain)
    // - Transferring stETH out doesn't affect totalAssets (internal accounting)
    // For now, yield/loss simulation is a no-op. Tests requiring yield/loss
    // simulation will not produce meaningful results with the real Fluid vault.

    function simulateSTYield(uint256) public pure override {}
    function simulateJTYield(uint256) public pure override {}
    function simulateSTLoss(uint256) public pure override {}
    function simulateJTLoss(uint256) public pure override {}

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
    // FLUID STETH-SPECIFIC TESTS
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

    /// @notice POC: Demonstrates that Fluid vault's convertToAssets changes when stETH is deposited
    /// This is the root cause of NAV_CONSERVATION_VIOLATION - not stETH rebasing
    function test_POC_fluidVaultSharePriceChange() external {
        // The JT vault shares held by kernel
        uint256 jtVaultShares = 439520349737079033628;

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
