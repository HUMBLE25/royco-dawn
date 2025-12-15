// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Vm } from "../../../lib/forge-std/src/Vm.sol";
import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC4626ST_AaveV3JT_Kernel } from "../../../src/kernels/ERC4626ST_AaveV3JT_Kernel.sol";
import { ConstantsLib } from "../../../src/libraries/ConstantsLib.sol";
import { RoycoKernelInitParams } from "../../../src/libraries/RoycoKernelStorageLib.sol";
import { RoycoVaultTranche } from "../../../src/tranches/RoycoVaultTranche.sol";
import { BaseTest } from "../../base/BaseTest.sol";
import { ERC4626Mock } from "../../mock/ERC4626Mock.sol";

abstract contract MainnetForkWithAaveTestBase is BaseTest {
    uint256 internal constant AAVE_MAX_ABS_NAV_DELTA = 2;

    Vm.Wallet internal RESERVE;
    address internal RESERVE_ADDRESS;

    // Deployed contracts
    ERC4626Mock internal mockStUnderlyingVault;
    ERC4626ST_AaveV3JT_Kernel internal erc4626STAaveV3JTKernel;

    // External Contracts
    IERC20 internal usdc = IERC20(ETHEREUM_MAINNET_USDC_ADDRESS);
    IERC20 internal aToken = IERC20(aTokenAddresses[1][ETHEREUM_MAINNET_USDC_ADDRESS]);

    constructor() {
        BETA_WAD = 0; // Different opportunities
    }

    function _setUpRoyco() internal override {
        // Setup wallets
        RESERVE = vm.createWallet("RESERVE");
        RESERVE_ADDRESS = RESERVE.addr;

        // Deploy core
        super._setUpRoyco();

        // Deal USDC to all configured addresses for mainnet fork tests
        _dealUSDCToAddresses();

        // Deploy mock senior tranche underlying vault
        mockStUnderlyingVault = new ERC4626Mock(ETHEREUM_MAINNET_USDC_ADDRESS, RESERVE_ADDRESS);
        vm.label(address(mockStUnderlyingVault), "MockSTUnderlyingVault");
        // Have the reserve approve the mock senior tranche underlying vault to spend USDC
        vm.prank(RESERVE_ADDRESS);
        IERC20(ETHEREUM_MAINNET_USDC_ADDRESS).approve(address(mockStUnderlyingVault), type(uint256).max);

        // Deploy the markets
        (RoycoVaultTranche seniorTranche_, RoycoVaultTranche juniorTranche_, ERC4626ST_AaveV3JT_Kernel erc4626STAaveV3JTKernel_, bytes32 marketId_) =
            _deployMarketWithKernel();
        _setDeployedMarket(seniorTranche_, juniorTranche_, erc4626STAaveV3JTKernel_, marketId_);
        erc4626STAaveV3JTKernel = erc4626STAaveV3JTKernel_;
    }

    /// @notice Deals USDC tokens to all configured addresses for mainnet fork tests
    /// @dev Each address receives 10M USDC (10_000_000e6) to ensure sufficient balance for testing
    function _dealUSDCToAddresses() internal {
        uint256 usdcAmount = 10_000_000e6; // 10M USDC (6 decimals)

        // Deal to admin/role addresses
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, OWNER_ADDRESS, usdcAmount);
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, PAUSER_ADDRESS, usdcAmount);
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, SCHEDULER_MANAGER_ADDRESS, usdcAmount);
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, UPGRADER_ADDRESS, usdcAmount);
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, PROTOCOL_FEE_RECIPIENT_ADDRESS, usdcAmount);

        // Deal to provider addresses
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, ALICE_ADDRESS, usdcAmount);
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, BOB_ADDRESS, usdcAmount);
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, CHARLIE_ADDRESS, usdcAmount);
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, DAN_ADDRESS, usdcAmount);

        // Deal to reserve address
        deal(ETHEREUM_MAINNET_USDC_ADDRESS, RESERVE_ADDRESS, usdcAmount);
    }

    function _deployMarketWithKernel()
        internal
        returns (RoycoVaultTranche seniorTranche_, RoycoVaultTranche juniorTranche_, ERC4626ST_AaveV3JT_Kernel kernel_, bytes32 marketId_)
    {
        // Deploy kernel
        kernel_ = ERC4626ST_AaveV3JT_Kernel(_deployKernel(address(erc4626ST_AaveV3JT_KernelImplementation), bytes("")));

        // Deploy market with kernel
        (seniorTranche_, juniorTranche_, marketId_) = _deployMarket(
            SENIOR_TRANCH_NAME,
            SENIOR_TRANCH_SYMBOL,
            JUNIOR_TRANCH_NAME,
            JUNIOR_TRANCH_SYMBOL,
            ETHEREUM_MAINNET_USDC_ADDRESS,
            ETHEREUM_MAINNET_USDC_ADDRESS,
            address(kernel_)
        );

        // Prepare kernel initialization parameters
        RoycoKernelInitParams memory params = RoycoKernelInitParams({
            seniorTranche: address(seniorTranche_),
            juniorTranche: address(juniorTranche_),
            coverageWAD: COVERAGE_WAD,
            betaWAD: BETA_WAD,
            rdm: address(rdm),
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT_ADDRESS,
            protocolFeeWAD: PROTOCOL_FEE_WAD
        });

        // Initialize the kernel
        kernel_.initialize(params, OWNER_ADDRESS, PAUSER_ADDRESS, address(mockStUnderlyingVault), ETHEREUM_MAINNET_AAVE_V3_POOL_ADDRESS);
    }

    /// @notice Returns the fork configuration
    /// @return forkBlock The fork block
    /// @return forkRpcUrl The fork RPC URL
    function _forkConfiguration() internal override returns (uint256 forkBlock, string memory forkRpcUrl) {
        forkBlock = 23_997_023;
        forkRpcUrl = vm.envString("MAINNET_RPC_URL");
        if (bytes(forkRpcUrl).length == 0) {
            fail("MAINNET_RPC_URL environment variable is not set");
        }
    }
}
