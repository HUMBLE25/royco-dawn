// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Vm } from "../../lib/forge-std/src/Vm.sol";
import { console2 } from "../../lib/forge-std/src/console2.sol";
import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IRoycoAccountant } from "../../src/interfaces/IRoycoAccountant.sol";
import { WAD, ZERO_TRANCHE_UNITS } from "../../src/libraries/Constants.sol";
import { AssetClaims, TrancheType } from "../../src/libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, toTrancheUnits, toUint256 } from "../../src/libraries/Units.sol";
import { UnitsMathLib } from "../../src/libraries/Units.sol";
import { MainnetForkWithAaveTestBase } from "./base/MainnetForkWithAaveBaseTest.t.sol";

contract BasicOperationsTest is MainnetForkWithAaveTestBase {
    using Math for uint256;
    using UnitsMathLib for TRANCHE_UNIT;
    using UnitsMathLib for NAV_UNIT;

    // Test State Trackers
    TrancheState internal stState;
    TrancheState internal jtState;

    function setUp() public {
        _setUpRoyco();
        _setUpTrancheRoles(providers, PAUSER_ADDRESS, UPGRADER_ADDRESS);
    }

    function testFuzz_depositIntoJT(uint256 _assets) external {
        // Bound assets to reasonable range (avoid zero and very large amounts)
        _assets = bound(_assets, 1e6, 1_000_000e6); // Between 1 USDC and 1M USDC (6 decimals)
        TRANCHE_UNIT assets = toTrancheUnits(_assets);

        address depositor = ALICE_ADDRESS;

        // Get initial balances
        uint256 initialDepositorBalance = USDC.balanceOf(depositor);
        uint256 initialTrancheShares = JT.balanceOf(depositor);

        // Assert that initially all tranche parameters are 0
        _verifyPreviewNAVs(stState, jtState, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, AAVE_MAX_ABS_NAV_DELTA);
        _verifyFeeTaken(stState, jtState, PROTOCOL_FEE_RECIPIENT_ADDRESS);

        // Approve the junior tranche to spend assets
        vm.prank(depositor);
        USDC.approve(address(JT), _assets);

        // Deposit into junior tranche
        vm.prank(depositor);
        uint256 shares = JT.deposit(assets, depositor, depositor);
        _updateOnDeposit(jtState, assets, _toJTValue(assets), shares, TrancheType.JUNIOR);

        // Verify shares were minted
        assertGt(shares, 0, "Shares should be greater than 0");
        assertEq(JT.balanceOf(depositor), initialTrancheShares + shares, "Depositor should receive shares");

        // Verify that maxRedeemable shares returns the correct amount
        uint256 maxRedeemableShares = JT.maxRedeem(depositor);
        assertApproxEqRel(maxRedeemableShares, shares, MAX_REDEEM_RELATIVE_DELTA, "Max redeemable shares should return the correct amount");
        assertTrue(maxRedeemableShares <= shares, "Max redeemable shares should be less than or equal to shares");

        // Verify that convertToAssets returns the correct amount
        TRANCHE_UNIT convertedAssets = JT.convertToAssets(shares).jtAssets;
        assertApproxEqRel(convertedAssets, assets, MAX_CONVERT_TO_ASSETS_RELATIVE_DELTA, "Convert to assets should return the correct amount");

        // We do not test previewRedeem here because it is expected to revert in async mode

        // Verify assets were transferred
        assertEq(USDC.balanceOf(depositor), initialDepositorBalance - _assets, "Depositor balance should decrease by assets amount");

        // Verify that an equivalent amount of AUSDCs were minted
        assertApproxEqAbs(
            AUSDC.balanceOf(address(KERNEL)), _assets, toUint256(AAVE_MAX_ABS_TRANCH_UNIT_DELTA), "An equivalent amount of AUSDCs should be minted"
        );

        // Verify that the tranche state has been updated
        _verifyPreviewNAVs(stState, jtState, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, AAVE_MAX_ABS_NAV_DELTA);
        _verifyFeeTaken(stState, jtState, PROTOCOL_FEE_RECIPIENT_ADDRESS);
    }

    function testFuzz_multipleDepositsIntoJT(uint256 _numDepositors, uint256 _amountSeed) external {
        // Bound the number of depositors to a reasonable range (avoid zero and very large numbers)
        _numDepositors = bound(_numDepositors, 1, 10);

        // Assert that initially all tranche parameters are 0
        _verifyPreviewNAVs(stState, jtState, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, AAVE_MAX_ABS_NAV_DELTA);
        _verifyFeeTaken(stState, jtState, PROTOCOL_FEE_RECIPIENT_ADDRESS);

        for (uint256 i = 0; i < _numDepositors; i++) {
            // Generate a provider
            Vm.Wallet memory provider = _generateProvider(i);

            // Generate a random amount
            uint256 amount = bound(uint256(keccak256(abi.encodePacked(_amountSeed, i))), 1e6, 1_000_000e6);
            TRANCHE_UNIT assets = toTrancheUnits(amount);

            // Get initial balances
            uint256 initialDepositorBalance = USDC.balanceOf(provider.addr);
            uint256 initialTrancheShares = JT.balanceOf(provider.addr);
            uint256 initialATokenBalance = AUSDC.balanceOf(address(KERNEL));

            // Approve the tranche to spend assets
            vm.prank(provider.addr);
            USDC.approve(address(JT), amount);

            // Deposit into the tranche
            vm.prank(provider.addr);
            uint256 shares = JT.deposit(assets, provider.addr, provider.addr);

            // Verify that an equivalent amount of AUSDCs were minted
            assertApproxEqAbs(
                AUSDC.balanceOf(address(KERNEL)),
                amount + initialATokenBalance,
                toUint256(AAVE_MAX_ABS_TRANCH_UNIT_DELTA),
                "An equivalent amount of AUSDCs should be minted"
            );

            uint256 aTokensMinted = AUSDC.balanceOf(address(KERNEL)) - initialATokenBalance;
            _updateOnDeposit(jtState, toTrancheUnits(aTokensMinted), _toJTValue(toTrancheUnits(aTokensMinted)), shares, TrancheType.JUNIOR);

            // Verify that shares were minted
            assertEq(JT.balanceOf(provider.addr), initialTrancheShares + shares, "Provider should receive shares");

            // Verify that maxRedeemable shares returns the correct amount
            uint256 maxRedeemableShares = JT.maxRedeem(provider.addr);
            assertApproxEqRel(maxRedeemableShares, shares, MAX_REDEEM_RELATIVE_DELTA, "Max redeemable shares should return the correct amount");
            assertTrue(maxRedeemableShares <= shares, "Max redeemable shares should be less than or equal to shares");

            // Verify that convertToAssets returns the correct amount
            TRANCHE_UNIT convertedAssets = JT.convertToAssets(shares).jtAssets;
            assertApproxEqRel(convertedAssets, assets, MAX_CONVERT_TO_ASSETS_RELATIVE_DELTA, "Convert to assets should return the correct amount");
            assertTrue(convertedAssets <= assets, "Convert to assets should be less than or equal to amount");

            // Verify that assets were transferred
            assertEq(USDC.balanceOf(provider.addr), initialDepositorBalance - amount, "Provider balance should decrease by amount");

            // Verify that the tranche state has been updated
            _verifyPreviewNAVs(stState, jtState, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, AAVE_MAX_ABS_NAV_DELTA);
            _verifyFeeTaken(stState, jtState, PROTOCOL_FEE_RECIPIENT_ADDRESS);
        }
    }

    function testFuzz_depositIntoST_verifyCoverageRequirementEnforcement(uint256 _jtAssets, uint256 _stDepositPercentage) external {
        // Bound assets to reasonable range (avoid zero and very large amounts)
        _jtAssets = bound(_jtAssets, 1e6, 1_000_000e6); // Between 1 USDC and 1M USDC (6 decimals)
        _stDepositPercentage = bound(_stDepositPercentage, 1, 100);
        TRANCHE_UNIT jtAssets = toTrancheUnits(_jtAssets);

        // There are no assets in JT initally, therefore depositing into ST should fail
        address stDepositor = BOB_ADDRESS;
        TRANCHE_UNIT stDepositAmount = toTrancheUnits(1);

        vm.startPrank(stDepositor);
        USDC.approve(address(ST), toUint256(stDepositAmount));
        vm.expectRevert(abi.encodeWithSelector(IRoycoAccountant.COVERAGE_REQUIREMENT_UNSATISFIED.selector));
        ST.deposit(stDepositAmount, stDepositor, stDepositor);
        vm.stopPrank();

        // Deposit assets into the junior tranche to allow deposits into the ST
        address jtDepositor = ALICE_ADDRESS;
        vm.startPrank(jtDepositor);
        USDC.approve(address(JT), _jtAssets);
        uint256 shares = JT.deposit(jtAssets, jtDepositor, jtDepositor);
        vm.stopPrank();

        _updateOnDeposit(jtState, jtAssets, _toJTValue(jtAssets), shares, TrancheType.JUNIOR);
        _verifyPreviewNAVs(stState, jtState, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, AAVE_MAX_ABS_NAV_DELTA);

        // Verify that ST.maxDeposit returns JTEff / coverage
        // BETA is 0
        TRANCHE_UNIT expectedMaxDeposit = toTrancheUnits(toUint256(JT.totalAssets().nav).mulDiv(WAD, COVERAGE_WAD, Math.Rounding.Floor));
        TRANCHE_UNIT maxDeposit = ST.maxDeposit(jtDepositor);
        assertEq(maxDeposit, expectedMaxDeposit, "Max deposit should return JTEff * coverage");

        // Try to deposit more than the max deposit, it should revert
        TRANCHE_UNIT depositAmount = expectedMaxDeposit + toTrancheUnits(1);
        vm.startPrank(stDepositor);
        USDC.approve(address(ST), toUint256(depositAmount));
        vm.expectRevert(abi.encodeWithSelector(IRoycoAccountant.COVERAGE_REQUIREMENT_UNSATISFIED.selector));
        ST.deposit(depositAmount, stDepositor, stDepositor);
        vm.stopPrank();

        //////////////////////////////////////////////////////
        /// Deposit a percentage of the max deposit into ST
        //////////////////////////////////////////////////////

        // Deposit a percentage of the max deposit
        depositAmount = expectedMaxDeposit.mulDiv(_stDepositPercentage, 100, Math.Rounding.Floor);
        vm.startPrank(stDepositor);
        USDC.approve(address(ST), toUint256(depositAmount));
        uint256 sharesMinted = ST.deposit(depositAmount, stDepositor, stDepositor);
        vm.stopPrank();

        // Assert that ST shares were minted to the user
        assertGt(sharesMinted, 0, "Shares should be greater than 0");
        assertEq(ST.balanceOf(stDepositor), sharesMinted, "User should receive shares");

        // Update the tranche state
        _updateOnDeposit(stState, depositAmount, _toSTValue(depositAmount), sharesMinted, TrancheType.SENIOR);

        // Verify that the tranche state has been updated
        _verifyPreviewNAVs(stState, jtState, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, AAVE_MAX_ABS_NAV_DELTA);
        _verifyFeeTaken(stState, jtState, PROTOCOL_FEE_RECIPIENT_ADDRESS);

        // Verify that the amount was transferred to the underlying vault
        assertEq(USDC.balanceOf(address(MOCK_UNDERLYING_ST_VAULT)), toUint256(depositAmount), "Amount should be transferred to the underlying vault");

        // Verify that underlying shares were minted to the kernel
        assertEq(MOCK_UNDERLYING_ST_VAULT.balanceOf(address(KERNEL)), toUint256(depositAmount), "Underlying shares should be minted to the kernel");

        // Verify that ST.maxDeposit went down
        expectedMaxDeposit = expectedMaxDeposit - depositAmount;
        assertEq(ST.maxDeposit(stDepositor), expectedMaxDeposit, "Max deposit should go down expected amount");

        // Verify that ST.convertToAssets returns the correct amount
        AssetClaims memory convertToAssetsResult = ST.convertToAssets(sharesMinted);
        assertApproxEqAbs(convertToAssetsResult.stAssets, depositAmount, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, "Convert to assets should return the correct amount");
        assertEq(convertToAssetsResult.jtAssets, ZERO_TRANCHE_UNITS, "Convert to assets should return 0 JT assets");
        assertApproxEqAbs(convertToAssetsResult.nav, _toSTValue(depositAmount), AAVE_MAX_ABS_NAV_DELTA, "Convert to assets should return the correct NAV");

        // Verify that ST.previewRedeem returns the correct amount
        AssetClaims memory previewRedeemResult = ST.previewRedeem(sharesMinted);
        assertApproxEqAbs(previewRedeemResult.stAssets, depositAmount, AAVE_MAX_ABS_TRANCH_UNIT_DELTA, "Preview redeem should return the correct amount");
        assertEq(previewRedeemResult.jtAssets, ZERO_TRANCHE_UNITS, "Preview redeem should return 0 JT assets");
        assertApproxEqAbs(previewRedeemResult.nav, _toSTValue(depositAmount), AAVE_MAX_ABS_NAV_DELTA, "Preview redeem should return the correct NAV");

        // Verify that ST.maxRedeem returns the correct amount
        uint256 maxRedeem = ST.maxRedeem(stDepositor);
        assertEq(maxRedeem, sharesMinted, "Max redeem should return the correct amount");
    }
}
