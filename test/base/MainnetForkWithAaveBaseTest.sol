// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ERC4626ST_AaveV3JT_Kernel } from "../../src/kernels/ERC4626ST_AaveV3JT_Kernel.sol";
import { ConstantsLib } from "../../src/libraries/ConstantsLib.sol";
import { RoycoKernelInitParams } from "../../src/libraries/RoycoKernelStorageLib.sol";
import { RoycoVaultTranche } from "../../src/tranches/RoycoVaultTranche.sol";
import { ERC4626Mock } from "../mock/ERC4626Mock.sol";
import { BaseTest } from "./BaseTest.sol";

contract MainnetForkWithAaveTestBase is BaseTest {
    // Fork Parameters
    uint256 internal constant FORK_BLOCK = 23_997_023;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    uint256 internal forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), FORK_BLOCK);

    // Deployed contracts
    ERC4626Mock internal mockStUnderlyingVault;
    RoycoVaultTranche internal seniorTranche;
    RoycoVaultTranche internal juniorTranche;
    ERC4626ST_AaveV3JT_Kernel internal erc4626STAaveV3JTKernel;
    bytes32 internal marketId;

    function setUp() public {
        vm.selectFork(forkId);

        _setUpRoyco();
    }

    function _setUpRoyco() internal override {
        // Deploy core
        super._setUpRoyco();

        // Deploy mock senior tranche underlying vault
        mockStUnderlyingVault = new ERC4626Mock(USDC);

        // Deploy the markets
        (seniorTranche, juniorTranche, erc4626STAaveV3JTKernel, marketId) = _deployMarketWithKernel();
    }

    /// @notice Deploys a market and initializes the kernel
    function _deployMarketWithKernel()
        internal
        returns (RoycoVaultTranche seniorTranche, RoycoVaultTranche juniorTranche, ERC4626ST_AaveV3JT_Kernel kernel, bytes32 marketId)
    {
        // Deploy kernel
        kernel = ERC4626ST_AaveV3JT_Kernel(_deployKernel(address(erc4626ST_AaveV3JT_KernelImplementation), bytes("")));

        // Deploy market with kernel
        (seniorTranche, juniorTranche, marketId) =
            _deployMarket(SENIOR_TRANCH_NAME, SENIOR_TRANCH_SYMBOL, JUNIOR_TRANCH_NAME, JUNIOR_TRANCH_SYMBOL, USDC, USDC, address(kernel));

        // Prepare kernel initialization parameters
        RoycoKernelInitParams memory params = RoycoKernelInitParams({
            seniorTranche: address(seniorTranche),
            juniorTranche: address(juniorTranche),
            coverageWAD: DEFAULT_COVERAGE_WAD,
            betaWAD: DEFAULT_BETA_WAD,
            rdm: address(rdm),
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT_ADDRESS,
            protocolFeeWAD: DEFAULT_PROTOCOL_FEE_WAD
        });

        // Initialize the kernel
        kernel.initialize(params, OWNER_ADDRESS, PAUSER_ADDRESS, address(mockStUnderlyingVault), AAVE_V3_POOL);
    }
}
