// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Initializable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "../../lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManaged } from "../../lib/openzeppelin-contracts/contracts/access/manager/IAccessManaged.sol";
import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { RoycoAccountant } from "../../src/accountant/RoycoAccountant.sol";
import { IRoycoAccountant } from "../../src/interfaces/IRoycoAccountant.sol";
import { IRoycoKernel } from "../../src/interfaces/kernel/IRoycoKernel.sol";
import { IRoycoVaultTranche } from "../../src/interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../../src/libraries/RoycoKernelStorageLib.sol";
import { TrancheDeploymentParams } from "../../src/libraries/Types.sol";
import { RoycoJT } from "../../src/tranches/RoycoJT.sol";
import { RoycoST } from "../../src/tranches/RoycoST.sol";
import {
    YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel
} from "../../src/kernels/YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel.sol";
import { RAY } from "../../src/libraries/Constants.sol";

import { YieldBearingERC4626_TestBase } from "./YieldBearingERC4626_ST_JT/base/YieldBearingERC4626_TestBase.t.sol";
import { IKernelTestHooks } from "../interfaces/IKernelTestHooks.sol";
import { NAV_UNIT, TRANCHE_UNIT, toNAVUnits, toTrancheUnits, toUint256 } from "../../src/libraries/Units.sol";

/// @title UpgradabilityTestSuite
/// @notice Tests upgradability of all Royco protocol contracts
/// @dev Tests that:
///      1. All contracts (ST, JT, Kernel, Accountant) are upgradeable by ADMIN_UPGRADER_ROLE
///      2. All implementations are non-initializable (constructor disables initializers)
///      3. Upgrades fail when called by non-upgrader addresses
contract UpgradabilityTestSuite is YieldBearingERC4626_TestBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // MAINNET ADDRESSES (sNUSD for testing)
    // ═══════════════════════════════════════════════════════════════════════════

    address internal constant SNUSD = 0x08EFCC2F3e61185D0EA7F8830B3FEc9Bfa2EE313;

    // ═══════════════════════════════════════════════════════════════════════════
    // NEW IMPLEMENTATION CONTRACTS FOR UPGRADE TESTING
    // ═══════════════════════════════════════════════════════════════════════════

    RoycoST internal newSTImpl;
    RoycoJT internal newJTImpl;
    RoycoAccountant internal newAccountantImpl;
    address internal newKernelImpl;

    // ═══════════════════════════════════════════════════════════════════════════
    // PROTOCOL CONFIGURATION (sNUSD)
    // ═══════════════════════════════════════════════════════════════════════════

    function getProtocolConfig() public pure override returns (ProtocolConfig memory) {
        return ProtocolConfig({
            name: "sNUSD_Upgradability",
            forkBlock: 24_270_513,
            forkRpcUrlEnvVar: "MAINNET_RPC_URL",
            stAsset: SNUSD,
            jtAsset: SNUSD,
            stDecimals: 18,
            jtDecimals: 18,
            initialFunding: 1_000_000e18
        });
    }

    function _getInitialConversionRate() internal pure override returns (uint256) {
        return RAY;
    }

    function maxTrancheUnitDelta() public pure override returns (TRANCHE_UNIT) {
        return toTrancheUnits(uint256(1e12));
    }

    function maxNAVDelta() public pure override returns (NAV_UNIT) {
        return toNAVUnits(uint256(1e12));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public override {
        super.setUp();

        // Deploy new implementations for upgrade testing
        _deployNewImplementations();
    }

    function _deployNewImplementations() internal {
        // Deploy new ST implementation
        newSTImpl = new RoycoST();
        vm.label(address(newSTImpl), "NewSTImpl");

        // Deploy new JT implementation
        newJTImpl = new RoycoJT();
        vm.label(address(newJTImpl), "NewJTImpl");

        // Deploy new Accountant implementation
        newAccountantImpl = new RoycoAccountant();
        vm.label(address(newAccountantImpl), "NewAccountantImpl");

        // Deploy new Kernel implementation with same constructor params
        IRoycoKernel.RoycoKernelConstructionParams memory constructionParams = IRoycoKernel.RoycoKernelConstructionParams({
            seniorTranche: address(ST),
            stAsset: config.stAsset,
            juniorTranche: address(JT),
            jtAsset: config.jtAsset
        });

        newKernelImpl =
            address(new YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel(constructionParams));
        vm.label(newKernelImpl, "NewKernelImpl");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 1: IMPLEMENTATIONS ARE NON-INITIALIZABLE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test that ST implementation cannot be initialized
    function test_stImplementation_cannotBeInitialized() external {
        TrancheDeploymentParams memory params =
            TrancheDeploymentParams({ name: "Test ST", symbol: "TST", kernel: address(KERNEL) });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ST_IMPL.initialize(params, config.stAsset, address(FACTORY), MARKET_ID);
    }

    /// @notice Test that JT implementation cannot be initialized
    function test_jtImplementation_cannotBeInitialized() external {
        TrancheDeploymentParams memory params =
            TrancheDeploymentParams({ name: "Test JT", symbol: "TJT", kernel: address(KERNEL) });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        JT_IMPL.initialize(params, config.jtAsset, address(FACTORY), MARKET_ID);
    }

    /// @notice Test that Accountant implementation cannot be initialized
    function test_accountantImplementation_cannotBeInitialized() external {
        IRoycoAccountant.RoycoAccountantInitParams memory params = IRoycoAccountant.RoycoAccountantInitParams({
            kernel: address(KERNEL),
            stProtocolFeeWAD: ST_PROTOCOL_FEE_WAD,
            jtProtocolFeeWAD: JT_PROTOCOL_FEE_WAD,
            coverageWAD: COVERAGE_WAD,
            betaWAD: BETA_WAD,
            lltvWAD: LLTV,
            ydm: address(YDM),
            ydmInitializationData: "",
            fixedTermDurationSeconds: FIXED_TERM_DURATION_SECONDS
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ACCOUNTANT_IMPL.initialize(params, address(FACTORY));
    }

    /// @notice Test that Kernel implementation cannot be initialized
    function test_kernelImplementation_cannotBeInitialized() external {
        RoycoKernelInitParams memory params = RoycoKernelInitParams({
            initialAuthority: address(FACTORY),
            accountant: address(ACCOUNTANT),
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT_ADDRESS,
            jtRedemptionDelayInSeconds: 1000
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel(KERNEL_IMPL).initialize(params, RAY);
    }

    /// @notice Test that new ST implementation cannot be initialized
    function test_newSTImplementation_cannotBeInitialized() external {
        TrancheDeploymentParams memory params =
            TrancheDeploymentParams({ name: "Test ST", symbol: "TST", kernel: address(KERNEL) });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        newSTImpl.initialize(params, config.stAsset, address(FACTORY), MARKET_ID);
    }

    /// @notice Test that new JT implementation cannot be initialized
    function test_newJTImplementation_cannotBeInitialized() external {
        TrancheDeploymentParams memory params =
            TrancheDeploymentParams({ name: "Test JT", symbol: "TJT", kernel: address(KERNEL) });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        newJTImpl.initialize(params, config.jtAsset, address(FACTORY), MARKET_ID);
    }

    /// @notice Test that new Accountant implementation cannot be initialized
    function test_newAccountantImplementation_cannotBeInitialized() external {
        IRoycoAccountant.RoycoAccountantInitParams memory params = IRoycoAccountant.RoycoAccountantInitParams({
            kernel: address(KERNEL),
            stProtocolFeeWAD: ST_PROTOCOL_FEE_WAD,
            jtProtocolFeeWAD: JT_PROTOCOL_FEE_WAD,
            coverageWAD: COVERAGE_WAD,
            betaWAD: BETA_WAD,
            lltvWAD: LLTV,
            ydm: address(YDM),
            ydmInitializationData: "",
            fixedTermDurationSeconds: FIXED_TERM_DURATION_SECONDS
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        newAccountantImpl.initialize(params, address(FACTORY));
    }

    /// @notice Test that new Kernel implementation cannot be initialized
    function test_newKernelImplementation_cannotBeInitialized() external {
        RoycoKernelInitParams memory params = RoycoKernelInitParams({
            initialAuthority: address(FACTORY),
            accountant: address(ACCOUNTANT),
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT_ADDRESS,
            jtRedemptionDelayInSeconds: 1000
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        YieldBearingERC4626_ST_YieldBearingERC4626_JT_IdenticalERC4626Assets_Kernel(newKernelImpl).initialize(
            params, RAY
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 2: UPGRADES BY UPGRADER ROLE SUCCEED
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test that ST can be upgraded by upgrader
    function test_stProxy_canBeUpgradedByUpgrader() external {
        // Get state before upgrade
        uint256 totalSupplyBefore = ST.totalSupply();
        string memory nameBefore = IERC4626(address(ST)).name();

        // Upgrade ST
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(ST)).upgradeToAndCall(address(newSTImpl), "");

        // Verify state is preserved
        assertEq(ST.totalSupply(), totalSupplyBefore, "Total supply should be preserved after upgrade");
        assertEq(IERC4626(address(ST)).name(), nameBefore, "Name should be preserved after upgrade");
    }

    /// @notice Test that JT can be upgraded by upgrader
    function test_jtProxy_canBeUpgradedByUpgrader() external {
        // Get state before upgrade
        uint256 totalSupplyBefore = JT.totalSupply();
        string memory nameBefore = IERC4626(address(JT)).name();

        // Upgrade JT
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(JT)).upgradeToAndCall(address(newJTImpl), "");

        // Verify state is preserved
        assertEq(JT.totalSupply(), totalSupplyBefore, "Total supply should be preserved after upgrade");
        assertEq(IERC4626(address(JT)).name(), nameBefore, "Name should be preserved after upgrade");
    }

    /// @notice Test that Accountant can be upgraded by upgrader
    function test_accountantProxy_canBeUpgradedByUpgrader() external {
        // Get state before upgrade
        uint64 coverageBefore = ACCOUNTANT.getState().coverageWAD;
        address kernelBefore = ACCOUNTANT.getState().kernel;

        // Upgrade Accountant
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(ACCOUNTANT)).upgradeToAndCall(address(newAccountantImpl), "");

        // Verify state is preserved
        assertEq(ACCOUNTANT.getState().coverageWAD, coverageBefore, "Coverage should be preserved after upgrade");
        assertEq(ACCOUNTANT.getState().kernel, kernelBefore, "Kernel should be preserved after upgrade");
    }

    /// @notice Test that Kernel can be upgraded by upgrader
    function test_kernelProxy_canBeUpgradedByUpgrader() external {
        // Get state before upgrade
        (address stBefore,, address jtBefore,, , address accountantBefore,) = KERNEL.getState();

        // Upgrade Kernel
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(KERNEL)).upgradeToAndCall(newKernelImpl, "");

        // Verify state is preserved
        (address stAfter,, address jtAfter,,,address accountantAfter,) = KERNEL.getState();
        assertEq(stAfter, stBefore, "ST address should be preserved after upgrade");
        assertEq(jtAfter, jtBefore, "JT address should be preserved after upgrade");
        assertEq(accountantAfter, accountantBefore, "Accountant should be preserved after upgrade");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 3: UPGRADES BY NON-UPGRADER FAIL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test that ST cannot be upgraded by non-upgrader (random user)
    function test_stProxy_cannotBeUpgradedByNonUpgrader() external {
        vm.prank(ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, ALICE_ADDRESS));
        UUPSUpgradeable(address(ST)).upgradeToAndCall(address(newSTImpl), "");
    }

    /// @notice Test that JT cannot be upgraded by non-upgrader (random user)
    function test_jtProxy_cannotBeUpgradedByNonUpgrader() external {
        vm.prank(ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, ALICE_ADDRESS));
        UUPSUpgradeable(address(JT)).upgradeToAndCall(address(newJTImpl), "");
    }

    /// @notice Test that Accountant cannot be upgraded by non-upgrader (random user)
    function test_accountantProxy_cannotBeUpgradedByNonUpgrader() external {
        vm.prank(ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, ALICE_ADDRESS));
        UUPSUpgradeable(address(ACCOUNTANT)).upgradeToAndCall(address(newAccountantImpl), "");
    }

    /// @notice Test that Kernel cannot be upgraded by non-upgrader (random user)
    function test_kernelProxy_cannotBeUpgradedByNonUpgrader() external {
        vm.prank(ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, ALICE_ADDRESS));
        UUPSUpgradeable(address(KERNEL)).upgradeToAndCall(newKernelImpl, "");
    }

    /// @notice Test that ST cannot be upgraded by owner (who is not upgrader)
    function test_stProxy_cannotBeUpgradedByOwner() external {
        // Owner is not the upgrader
        vm.prank(OWNER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, OWNER_ADDRESS));
        UUPSUpgradeable(address(ST)).upgradeToAndCall(address(newSTImpl), "");
    }

    /// @notice Test that Kernel cannot be upgraded by pauser
    function test_kernelProxy_cannotBeUpgradedByPauser() external {
        vm.prank(PAUSER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, PAUSER_ADDRESS));
        UUPSUpgradeable(address(KERNEL)).upgradeToAndCall(newKernelImpl, "");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 4: STATE PRESERVATION AFTER UPGRADE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test that JT state is preserved after upgrade with deposits
    function testFuzz_jtProxy_statePreservedAfterUpgrade_withDeposits(uint256 _amount) external {
        _amount = bound(_amount, _minDepositAmount(), config.initialFunding / 4);

        // Deposit to JT
        uint256 shares = _depositJT(ALICE_ADDRESS, _amount);

        // Record state before upgrade
        uint256 totalSupplyBefore = JT.totalSupply();
        uint256 aliceBalanceBefore = JT.balanceOf(ALICE_ADDRESS);
        NAV_UNIT rawNAVBefore = JT.getRawNAV();

        // Upgrade JT
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(JT)).upgradeToAndCall(address(newJTImpl), "");

        // Verify state is preserved
        assertEq(JT.totalSupply(), totalSupplyBefore, "Total supply should be preserved");
        assertEq(JT.balanceOf(ALICE_ADDRESS), aliceBalanceBefore, "Alice balance should be preserved");
        assertEq(JT.getRawNAV(), rawNAVBefore, "Raw NAV should be preserved");
        assertEq(JT.balanceOf(ALICE_ADDRESS), shares, "Shares should match original deposit");
    }

    /// @notice Test that ST state is preserved after upgrade with deposits
    function testFuzz_stProxy_statePreservedAfterUpgrade_withDeposits(uint256 _jtAmount, uint256 _stPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount() * 10, config.initialFunding / 4);
        _stPercentage = bound(_stPercentage, 10, 50);

        // Deposit to JT first (for coverage)
        _depositJT(BOB_ADDRESS, _jtAmount);

        // Calculate ST amount based on max deposit to satisfy coverage
        TRANCHE_UNIT stMaxDeposit = ST.maxDeposit(ALICE_ADDRESS);
        uint256 stAmount = toUint256(stMaxDeposit) * _stPercentage / 100;
        if (stAmount < _minDepositAmount()) return;

        // Deposit to ST
        uint256 shares = _depositST(ALICE_ADDRESS, stAmount);

        // Record state before upgrade
        uint256 totalSupplyBefore = ST.totalSupply();
        uint256 aliceBalanceBefore = ST.balanceOf(ALICE_ADDRESS);
        NAV_UNIT rawNAVBefore = ST.getRawNAV();

        // Upgrade ST
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(ST)).upgradeToAndCall(address(newSTImpl), "");

        // Verify state is preserved
        assertEq(ST.totalSupply(), totalSupplyBefore, "Total supply should be preserved");
        assertEq(ST.balanceOf(ALICE_ADDRESS), aliceBalanceBefore, "Alice balance should be preserved");
        assertEq(ST.getRawNAV(), rawNAVBefore, "Raw NAV should be preserved");
        assertEq(ST.balanceOf(ALICE_ADDRESS), shares, "Shares should match original deposit");
    }

    /// @notice Test operations still work after upgrade
    function testFuzz_jtProxy_operationsWorkAfterUpgrade(uint256 _amount) external {
        _amount = bound(_amount, _minDepositAmount(), config.initialFunding / 4);

        // Deposit before upgrade
        uint256 sharesBefore = _depositJT(ALICE_ADDRESS, _amount);

        // Upgrade JT
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(JT)).upgradeToAndCall(address(newJTImpl), "");

        // Deposit after upgrade should still work
        uint256 sharesAfter = _depositJT(BOB_ADDRESS, _amount);

        // Both deposits should have resulted in shares
        assertGt(sharesBefore, 0, "Shares before upgrade should be > 0");
        assertGt(sharesAfter, 0, "Shares after upgrade should be > 0");

        // Total supply should reflect both deposits
        assertGe(JT.totalSupply(), sharesBefore + sharesAfter, "Total supply should include both deposits");
    }

    /// @notice Test kernel sync still works after upgrade
    function testFuzz_kernelProxy_syncWorksAfterUpgrade(uint256 _jtAmount, uint256 _yieldPercentage) external {
        _jtAmount = bound(_jtAmount, _minDepositAmount() * 10, config.initialFunding / 4);
        _yieldPercentage = bound(_yieldPercentage, 1, 10);

        // Setup: deposit JT
        _depositJT(ALICE_ADDRESS, _jtAmount);

        // Upgrade kernel
        vm.prank(UPGRADER_ADDRESS);
        UUPSUpgradeable(address(KERNEL)).upgradeToAndCall(newKernelImpl, "");

        // Simulate yield
        this.simulateJTYield(_yieldPercentage * 1e16);

        // Sync should still work after upgrade
        vm.prank(OWNER_ADDRESS);
        KERNEL.syncTrancheAccounting();

        // Should not revert - sync completed successfully
    }
}
