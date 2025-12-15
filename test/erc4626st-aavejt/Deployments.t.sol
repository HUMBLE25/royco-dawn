// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20Metadata } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPool } from "../../src/interfaces/aave/IPool.sol";
import { IRoycoKernel } from "../../src/interfaces/kernel/IRoycoKernel.sol";
import { RoycoKernelState } from "../../src/libraries/RoycoKernelStorageLib.sol";
import { MainnetForkWithAaveTestBase } from "./base/MainnetForkWithAaveBaseTest.sol";

contract DeploymentsTest is MainnetForkWithAaveTestBase {
    constructor() {
        BETA_WAD = 1e18; // Same opportunities
    }

    function setUp() public {
        _setUpRoyco();
    }

    /// @notice Verifies senior tranche deployment parameters
    function test_SeniorTrancheDeployment() public {
        // Basic wiring
        assertTrue(address(seniorTranche) != address(0), "Senior tranche not deployed");
        // Kernel wiring
        assertEq(seniorTranche.kernel(), address(kernel), "ST kernel address mismatch");
        assertEq(seniorTranche.marketId(), marketId, "ST marketId mismatch");

        // Asset and metadata
        assertEq(address(seniorTranche.asset()), ETHEREUM_MAINNET_USDC_ADDRESS, "ST asset should be USDC");
        assertEq(seniorTranche.name(), SENIOR_TRANCH_NAME, "ST name mismatch");
        assertEq(seniorTranche.symbol(), SENIOR_TRANCH_SYMBOL, "ST symbol mismatch");

        // Initial NAV and totals
        assertEq(seniorTranche.totalSupply(), 0, "ST initial totalSupply should be 0");
        assertEq(seniorTranche.getRawNAV(), 0, "ST initial raw NAV should be 0");
        assertEq(seniorTranche.getEffectiveNAV(), 0, "ST initial effective NAV should be 0");
        assertEq(seniorTranche.totalAssets(), 0, "ST initial total assets should be 0");
    }

    /// @notice Verifies junior tranche deployment parameters
    function test_JuniorTrancheDeployment() public {
        // Basic wiring
        assertTrue(address(juniorTranche) != address(0), "Junior tranche not deployed");
        // Kernel wiring
        assertEq(juniorTranche.kernel(), address(kernel), "JT kernel address mismatch");
        assertEq(juniorTranche.marketId(), marketId, "JT marketId mismatch");

        // Asset and metadata
        assertEq(address(juniorTranche.asset()), ETHEREUM_MAINNET_USDC_ADDRESS, "JT asset should be USDC");
        assertEq(juniorTranche.name(), JUNIOR_TRANCH_NAME, "JT name mismatch");
        assertEq(juniorTranche.symbol(), JUNIOR_TRANCH_SYMBOL, "JT symbol mismatch");

        // Initial NAV and totals
        assertEq(juniorTranche.totalSupply(), 0, "JT initial totalSupply should be 0");
        assertEq(juniorTranche.getRawNAV(), 0, "JT initial raw NAV should be 0");
        assertEq(juniorTranche.getEffectiveNAV(), 0, "JT initial effective NAV should be 0");
        assertEq(juniorTranche.totalAssets(), 0, "JT initial total assets should be 0");
    }

    /// @notice Verifies kernel deployment parameters and wiring
    function test_KernelDeployment() public {
        // Basic wiring
        assertTrue(address(erc4626STAaveV3JTKernel) != address(0), "Kernel not deployed");

        IRoycoKernel kernelIface = IRoycoKernel(address(erc4626STAaveV3JTKernel));

        // Verify kernel configuration via getKernelState
        RoycoKernelState memory state = kernelIface.getKernelState();

        // Tranche wiring
        assertEq(state.seniorTranche, address(seniorTranche), "Kernel seniorTranche mismatch");
        assertEq(state.juniorTranche, address(juniorTranche), "Kernel juniorTranche mismatch");

        // Coverage, beta, protocol fee configuration
        assertEq(state.coverageWAD, COVERAGE_WAD, "Kernel coverageWAD mismatch");
        assertEq(BETA_WAD, 1e18, "BETA_WAD mismatch");
        assertEq(state.betaWAD, BETA_WAD, "Kernel betaWAD mismatch");
        assertEq(state.protocolFeeRecipient, PROTOCOL_FEE_RECIPIENT_ADDRESS, "Kernel protocolFeeRecipient mismatch");
        assertEq(state.protocolFeeWAD, PROTOCOL_FEE_WAD, "Kernel protocolFeeWAD mismatch");

        // RDM wiring
        assertEq(state.rdm, address(rdm), "Kernel RDM mismatch");

        // Initial NAV / assets via kernel view functions
        assertEq(kernelIface.getSTTotalEffectiveAssets(), 0, "Kernel ST total effective assets should be 0");
        assertEq(kernelIface.getJTTotalEffectiveAssets(), 0, "Kernel JT total effective assets should be 0");
        assertEq(kernelIface.getSTRawNAV(), 0, "Kernel ST raw NAV should be 0");
        assertEq(kernelIface.getJTRawNAV(), 0, "Kernel JT raw NAV should be 0");

        // Aave wiring: pool and aToken mapping must be consistent
        address expectedAToken = IPool(ETHEREUM_MAINNET_AAVE_V3_POOL_ADDRESS).getReserveAToken(ETHEREUM_MAINNET_USDC_ADDRESS);
        assertEq(expectedAToken, address(aToken), "aToken address should match Aave pool data");
    }
}
