// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { Vm } from "../../lib/forge-std/src/Vm.sol";
import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RoycoTrancheFactory } from "../../src/RoycoTrancheFactory.sol";
import { RoycoAuth, RoycoRoles } from "../../src/auth/RoycoAuth.sol";
import { IRoycoKernel } from "../../src/interfaces/kernel/IRoycoKernel.sol";
import { ERC4626ST_AaveV3JT_Kernel } from "../../src/kernels/ERC4626ST_AaveV3JT_Kernel.sol";
import { ConstantsLib } from "../../src/libraries/ConstantsLib.sol";
import { RoycoKernelInitParams } from "../../src/libraries/RoycoKernelStorageLib.sol";
import { StaticCurveRDM } from "../../src/rdm/StaticCurveRDM.sol";
import { RoycoJT } from "../../src/tranches/RoycoJT.sol";
import { RoycoST } from "../../src/tranches/RoycoST.sol";
import { RoycoVaultTranche } from "../../src/tranches/RoycoVaultTranche.sol";

contract BaseTest is Test {
    // -----------------------------------------
    // Test Wallets
    // -----------------------------------------
    Vm.Wallet internal OWNER;
    address internal OWNER_ADDRESS;

    Vm.Wallet internal PAUSER;
    address internal PAUSER_ADDRESS;

    Vm.Wallet internal SCHEDULER_MANAGER;
    address internal SCHEDULER_MANAGER_ADDRESS;

    Vm.Wallet internal UPGRADER;
    address internal UPGRADER_ADDRESS;

    Vm.Wallet internal PROTOCOL_FEE_RECIPIENT;
    address internal PROTOCOL_FEE_RECIPIENT_ADDRESS;

    Vm.Wallet internal ALICE;
    Vm.Wallet internal BOB;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal DAN;

    address internal ALICE_ADDRESS;
    address internal BOB_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address internal DAN_ADDRESS;

    address[] internal providers;

    // -----------------------------------------
    // Assets
    // -----------------------------------------

    ERC20Mock internal mockUSDC;
    ERC20Mock internal mockUSDT;
    ERC20Mock internal mockDAI;
    address[] internal assets;

    // -----------------------------------------
    // Royco Deployments
    // -----------------------------------------

    RoycoTrancheFactory public factory;
    StaticCurveRDM public rdm;
    RoycoST public stImplementation;
    RoycoJT public jtImplementation;
    ERC4626ST_AaveV3JT_Kernel public erc4626ST_AaveV3JT_KernelImplementation;

    // -----------------------------------------
    // Royco Deployments Parameters
    // -----------------------------------------

    uint256 internal SEED_AMOUNT;
    string internal SENIOR_TRANCH_NAME = "Royco Senior Tranche";
    string internal SENIOR_TRANCH_SYMBOL = "RST";
    string internal JUNIOR_TRANCH_NAME = "Royco Junior Tranche";
    string internal JUNIOR_TRANCH_SYMBOL = "RJT";
    uint64 internal DEFAULT_COVERAGE_WAD = 0.2e18; // 20% coverage
    uint96 internal DEFAULT_BETA_WAD = 1e18; // 100% beta (same opportunity)
    uint64 internal DEFAULT_PROTOCOL_FEE_WAD = 0.01e18; // 1% protocol fee

    modifier prankModifier(address _pranker) {
        vm.startPrank(_pranker);
        _;
        vm.stopPrank();
    }

    function _setUpRoyco() internal virtual {
        _setupWallets();
        _setupAssets(10_000_000_000);

        // Deploy RDM
        rdm = new StaticCurveRDM();

        // Deploy tranche implementations
        stImplementation = new RoycoST();
        jtImplementation = new RoycoJT();

        // Deploy kernel implementation
        erc4626ST_AaveV3JT_KernelImplementation = new ERC4626ST_AaveV3JT_Kernel();

        // Deploy factory
        factory = new RoycoTrancheFactory(address(stImplementation), address(jtImplementation));
    }

    function _setupAssets(uint256 _seedAmount) internal {
        mockUSDC = new ERC20Mock();
        mockUSDC.mint(OWNER_ADDRESS, _seedAmount * (10 ** 18));
        mockUSDC.mint(ALICE_ADDRESS, _seedAmount * (10 ** 18));
        mockUSDC.mint(BOB_ADDRESS, _seedAmount * (10 ** 18));
        assets.push(address(mockUSDC));

        mockUSDT = new ERC20Mock();
        mockUSDT.mint(OWNER_ADDRESS, _seedAmount * (10 ** 18));
        mockUSDT.mint(ALICE_ADDRESS, _seedAmount * (10 ** 18));
        mockUSDT.mint(BOB_ADDRESS, _seedAmount * (10 ** 18));
        assets.push(address(mockUSDT));

        mockDAI = new ERC20Mock();
        mockDAI.mint(OWNER_ADDRESS, _seedAmount * (10 ** 18));
        mockDAI.mint(ALICE_ADDRESS, _seedAmount * (10 ** 18));
        mockDAI.mint(BOB_ADDRESS, _seedAmount * (10 ** 18));
        assets.push(address(mockDAI));
    }

    function _setupWallets() internal {
        // Init wallets with 1000 ETH each
        OWNER = _initWallet("OWNER", 1000 ether);
        PAUSER = _initWallet("PAUSER", 1000 ether);
        SCHEDULER_MANAGER = _initWallet("SCHEDULER_MANAGER", 1000 ether);
        UPGRADER = _initWallet("UPGRADER", 1000 ether);
        ALICE = _initWallet("ALICE", 1000 ether);
        BOB = _initWallet("BOB", 1000 ether);
        CHARLIE = _initWallet("CHARLIE", 1000 ether);
        DAN = _initWallet("DAN", 1000 ether);
        PROTOCOL_FEE_RECIPIENT = _initWallet("PROTOCOL_FEE_RECIPIENT", 1000 ether);

        // Set addresses
        OWNER_ADDRESS = OWNER.addr;
        PAUSER_ADDRESS = PAUSER.addr;
        SCHEDULER_MANAGER_ADDRESS = SCHEDULER_MANAGER.addr;
        UPGRADER_ADDRESS = UPGRADER.addr;
        ALICE_ADDRESS = ALICE.addr;
        BOB_ADDRESS = BOB.addr;
        CHARLIE_ADDRESS = CHARLIE.addr;
        DAN_ADDRESS = DAN.addr;
        PROTOCOL_FEE_RECIPIENT_ADDRESS = PROTOCOL_FEE_RECIPIENT.addr;

        providers.push(ALICE_ADDRESS);
        providers.push(BOB_ADDRESS);
        providers.push(CHARLIE_ADDRESS);
        providers.push(DAN_ADDRESS);
    }

    function _initWallet(string memory _name, uint256 _amount) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = vm.createWallet(_name);
        vm.label(wallet.addr, _name);
        vm.deal(wallet.addr, _amount);
        return wallet;
    }

    /// @notice Sets up roles for a tranche
    /// @param _tranche The tranche address
    /// @param _providers The providers addresses
    /// @param _pauser The pauser address
    /// @param _upgrader The upgrader address
    /// @param _schedulerManager The scheduler manager address
    function _setUpTrancheRoles(
        address _tranche,
        address[] memory _providers,
        address _pauser,
        address _upgrader,
        address _schedulerManager
    )
        internal
        prankModifier(OWNER_ADDRESS)
    {
        RoycoVaultTranche tranche = RoycoVaultTranche(_tranche);
        tranche.grantRole(RoycoRoles.PAUSER_ROLE, _pauser);
        tranche.grantRole(RoycoRoles.UPGRADER_ROLE, _upgrader);
        tranche.grantRole(RoycoRoles.SCHEDULER_MANAGER_ROLE, _schedulerManager);
        for (uint256 i = 0; i < _providers.length; i++) {
            tranche.grantRole(RoycoRoles.DEPOSIT_ROLE, _providers[i]);
            tranche.grantRole(RoycoRoles.REDEEM_ROLE, _providers[i]);
        }
    }

    /// @notice Sets up roles for a kernel
    /// @param _kernel The kernel address
    /// @param _schedulerManager The scheduler manager address
    /// @param _kernelAdmin The kernel admin address
    function _setUpKernelRoles(address _kernel, address _schedulerManager, address _kernelAdmin) internal prankModifier(OWNER_ADDRESS) {
        RoycoAuth __kernel = RoycoAuth(_kernel);
        __kernel.grantRole(RoycoRoles.SCHEDULER_MANAGER_ROLE, _schedulerManager);
        __kernel.grantRole(RoycoRoles.KERNEL_ADMIN_ROLE, _kernelAdmin);
    }

    /// @notice Deploys a market using the factory
    /// @param _seniorTrancheName Name of the senior tranche
    /// @param _seniorTrancheSymbol Symbol of the senior tranche
    /// @param _juniorTrancheName Name of the junior tranche
    /// @param _juniorTrancheSymbol Symbol of the junior tranche
    /// @param _seniorAsset Asset for the senior tranche
    /// @param _juniorAsset Asset for the junior tranche
    /// @param _kernel Address of the kernel contract
    function _deployMarket(
        string memory _seniorTrancheName,
        string memory _seniorTrancheSymbol,
        string memory _juniorTrancheName,
        string memory _juniorTrancheSymbol,
        address _seniorAsset,
        address _juniorAsset,
        address _kernel
    )
        internal
        returns (RoycoVaultTranche seniorTranche, RoycoVaultTranche juniorTranche, bytes32 marketId)
    {
        marketId = keccak256(abi.encode(_seniorTrancheName, _juniorTrancheName, block.timestamp));

        (address _seniorTranche, address _juniorTranche) = factory.deployMarket(
            _seniorTrancheName,
            _seniorTrancheSymbol,
            _juniorTrancheName,
            _juniorTrancheSymbol,
            _seniorAsset,
            _juniorAsset,
            _kernel,
            OWNER_ADDRESS,
            PAUSER_ADDRESS,
            marketId
        );

        seniorTranche = RoycoVaultTranche(_seniorTranche);
        juniorTranche = RoycoVaultTranche(_juniorTranche);
    }

    /// @notice Deploys a kernel using ERC1967 proxy
    /// @param _kernelImplementation The implementation address
    /// @param _kernelInitData The initialization data
    /// @return kernelProxy The deployed proxy address
    function _deployKernel(address _kernelImplementation, bytes memory _kernelInitData) internal returns (address kernelProxy) {
        kernelProxy = address(new ERC1967Proxy(_kernelImplementation, _kernelInitData));
    }
}
