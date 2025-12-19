// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Vm } from "../../lib/forge-std/src/Vm.sol";
import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IRoycoAccountant } from "../../src/interfaces/IRoycoAccountant.sol";
import { IRoycoKernel } from "../../src/interfaces/kernel/IRoycoKernel.sol";
import { ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, WAD, ZERO_TRANCHE_UNITS } from "../../src/libraries/Constants.sol";
import { AssetClaims, TrancheType } from "../../src/libraries/Types.sol";
import { SyncedAccountingState } from "../../src/libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, toTrancheUnits, toUint256 } from "../../src/libraries/Units.sol";
import { UnitsMathLib } from "../../src/libraries/Units.sol";
import { MainnetForkWithAaveTestBase } from "./base/MainnetForkWithAaveBaseTest.t.sol";

contract LossWaterfall is MainnetForkWithAaveTestBase {
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

    function testFuzz_jtLoss(uint256 _assets) external {
        // Bound assets to reasonable range (avoid zero and very large amounts)
        _assets = bound(_assets, 10e6, 1_000_000e6); // Between 1 USDC and 1M USDC (6 decimals)

        address depositor = ALICE_ADDRESS;

        // Approve the junior tranche to spend assets
        vm.prank(depositor);
        USDC.approve(address(JT), _assets);

        // Deposit into junior tranche
        vm.prank(depositor);
        uint256 shares = JT.deposit(toTrancheUnits(_assets), depositor, depositor);
        AssetClaims memory postDepositUserClaims = JT.convertToAssets(shares);
        (SyncedAccountingState memory postDepositState, AssetClaims memory postDepositTotalClaims,) = KERNEL.previewSyncTrancheAccounting(TrancheType.JUNIOR);

        // Simulate a loss by transferring out A Tokens from the kernel
        uint256 lossAssets = bound(_assets, 1e6, _assets - 1);
        vm.prank(address(KERNEL));
        AUSDC.transfer(BOB_ADDRESS, lossAssets);
        AssetClaims memory postLossUserClaims = JT.convertToAssets(shares);
        (SyncedAccountingState memory postLossState, AssetClaims memory postLossTotalClaims,) = KERNEL.previewSyncTrancheAccounting(TrancheType.JUNIOR);

        // Assert that the accounting reflects the JT loss
        assertApproxEqRel(
            toUint256(postDepositTotalClaims.jtAssets - postLossTotalClaims.jtAssets),
            lossAssets,
            MAX_CONVERT_TO_ASSETS_RELATIVE_DELTA,
            "JT claims must reflect the loss"
        );
        assertApproxEqRel(
            toUint256(postDepositUserClaims.jtAssets - postLossUserClaims.jtAssets),
            lossAssets,
            MAX_CONVERT_TO_ASSETS_RELATIVE_DELTA,
            "JT LP claims must reflect the loss"
        );
        assertApproxEqRel(
            toUint256(postDepositState.jtRawNAV - postLossState.jtRawNAV), lossAssets, MAX_CONVERT_TO_ASSETS_RELATIVE_DELTA, "JT raw NAV must reflect the loss"
        );
        assertApproxEqRel(
            toUint256(postDepositState.jtEffectiveNAV - postLossState.jtEffectiveNAV),
            lossAssets,
            MAX_CONVERT_TO_ASSETS_RELATIVE_DELTA,
            "JT raw NAV must reflect the loss"
        );
    }

    function testFuzz_jtGain(uint256 _assets, uint256 _timeToTravel) external {
        // Bound assets to reasonable range (avoid zero and very large amounts)
        _assets = bound(_assets, 10e6, 1_000_000e6); // Between 1 USDC and 1M USDC (6 decimals)
        _timeToTravel = bound(_timeToTravel, 1 hours, 365 days);

        address depositor = ALICE_ADDRESS;

        // Approve the junior tranche to spend assets
        vm.prank(depositor);
        USDC.approve(address(JT), _assets);

        // Deposit into junior tranche
        vm.prank(depositor);
        uint256 shares = JT.deposit(toTrancheUnits(_assets), depositor, depositor);
        AssetClaims memory postDepositUserClaims = JT.convertToAssets(shares);
        (SyncedAccountingState memory postDepositState, AssetClaims memory postDepositTotalClaims,) = KERNEL.previewSyncTrancheAccounting(TrancheType.JUNIOR);

        // Time travel
        skip(_timeToTravel);

        // Check the state after interest accrued
        AssetClaims memory postGainUserClaims = JT.convertToAssets(shares);
        (SyncedAccountingState memory postGainState, AssetClaims memory postGainTotalClaims,) = KERNEL.previewSyncTrancheAccounting(TrancheType.JUNIOR);

        // Assert that the accounting reflects the JT gain
        assertGt(toUint256(postGainState.jtProtocolFeeAccrued), 0, "Protocol fees accrued gain");
        assertGt(toUint256(postGainTotalClaims.jtAssets), toUint256(postDepositTotalClaims.jtAssets), "JT claims must reflect the gain");
        assertGt(toUint256(postGainUserClaims.jtAssets), toUint256(postDepositUserClaims.jtAssets), "JT LP claims must reflect the gain");
        assertGt(toUint256(postGainState.jtRawNAV), toUint256(postDepositState.jtRawNAV), "JT raw NAV must reflect the gain");
        assertGt(toUint256(postGainState.jtEffectiveNAV), toUint256(postDepositState.jtEffectiveNAV), "JT effective NAV must reflect the gain");
    }
}
