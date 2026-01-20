// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Vm } from "../../../lib/forge-std/src/Vm.sol";
import { Math } from "../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IRoycoAccountant } from "../../../src/interfaces/IRoycoAccountant.sol";
import { IRoycoKernel } from "../../../src/interfaces/kernel/IRoycoKernel.sol";
import { IRoycoVaultTranche } from "../../../src/interfaces/tranche/IRoycoVaultTranche.sol";
import { ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, WAD, ZERO_TRANCHE_UNITS } from "../../../src/libraries/Constants.sol";
import { AssetClaims, TrancheType } from "../../../src/libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, toTrancheUnits, toUint256 } from "../../../src/libraries/Units.sol";
import { UnitsMathLib } from "../../../src/libraries/Units.sol";
import { MainnetForkWithAaveTestBase } from "./base/MainnetForkWithAaveBaseTest.t.sol";

contract POCTest is MainnetForkWithAaveTestBase {
    using Math for uint256;
    using UnitsMathLib for TRANCHE_UNIT;
    using UnitsMathLib for NAV_UNIT;

    // Test State Trackers
    TrancheState internal stState;
    TrancheState internal jtState;

    /// Deploy a market with
    /// - Senior Tranche deployed into a ERC4626 compliant vault, with USDC as the underlying asset
    /// - Junior Tranche deployed into Aave V3, with USDC as the underlying asset
    /// - In Kind Assets Quoter
    /// - Adaptive Curve YDM
    function setUp() public {
        _setUpRoyco();
    }
}
