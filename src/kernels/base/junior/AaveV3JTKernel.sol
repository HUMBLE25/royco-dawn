// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IPool } from "../../../interfaces/aave/IPool.sol";
import { IPoolAddressesProvider } from "../../../interfaces/aave/IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "../../../interfaces/aave/IPoolDataProvider.sol";
import { ExecutionModel, IRoycoKernel } from "../../../interfaces/kernel/IRoycoKernel.sol";
import { ZERO_TRANCHE_UNITS } from "../../../libraries/Constants.sol";
import { NAV_UNIT, TRANCHE_UNIT, UnitsMathLib, toTrancheUnits, toUint256 } from "../../../libraries/Units.sol";
import { UtilsLib } from "../../../libraries/UtilsLib.sol";
import { AssetClaims, Operation, RoycoKernel, RoycoKernelStorageLib, SyncedAccountingState, TrancheType } from "../RoycoKernel.sol";
import { RedemptionDelayJTKernel } from "./base/RedemptionDelayJTKernel.sol";

abstract contract AaveV3JTKernel is RoycoKernel, RedemptionDelayJTKernel {
    using SafeERC20 for IERC20;
    using UnitsMathLib for TRANCHE_UNIT;

    /// @dev Storage slot for AaveV3JTKernelState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.AaveV3JTKernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AAVE_V3_JT_KERNEL_STORAGE_SLOT = 0x020a998929d5f52fd2ab88c68a53f71f586f1008b18ca7e45b22d0acddbf3e00;

    /**
     * @notice Storage state for the Royco Aave V3 Kernel
     * @custom:storage-location erc7201:Royco.storage.AaveV3JTKernelState
     * @custom:field pool - The address of the Aave V3 pool
     * @custom:field poolAddressesProvider - The address of the Aave V3 pool addresses provider
     * @custom:field jtAssetAToken - The address of the junior tranche base asset's A Token
     */
    struct AaveV3JTKernelState {
        address pool;
        address poolAddressesProvider;
        address jtAssetAToken;
    }

    /// @inheritdoc IRoycoKernel
    ExecutionModel public constant JT_INCREASE_NAV_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IRoycoKernel
    ExecutionModel public constant JT_DECREASE_NAV_EXECUTION_MODEL = ExecutionModel.ASYNC;

    /// @notice Thrown when the JT base asset is not a supported reserve token in the Aave V3 Pool
    error UNSUPPORTED_RESERVE_TOKEN();

    /// @notice Thrown when the shares to redeem are greater than the claimable shares
    error INSUFFICIENT_CLAIMABLE_SHARES(uint256 sharesToRedeem, uint256 claimableShares);

    /// @notice Thrown when a low-level call fails
    error FAILED_CALL();

    /**
     * @notice Initializes a kernel where the junior tranche is deployed into Aave V3 with a redemption delay
     * @param _aaveV3Pool The address of the Aave V3 Pool
     * @param _jtAsset The address of the base asset of the junior tranche
     * @param _jtRedemptionDelaySeconds The delay in seconds between a junior tranche LP requesting a redemption and being able to execute it
     */
    function __AaveV3_JT_Kernel_init(address _aaveV3Pool, address _jtAsset, uint256 _jtRedemptionDelaySeconds) internal onlyInitializing {
        // Initialize the async redemption delay kernel state
        __RedemptionDelay_JT_Kernel_init_unchained(_jtRedemptionDelaySeconds);
        // Initializes the Aave V3 junior tranche kernel state
        __AaveV3_JT_Kernel_init_unchained(_aaveV3Pool, _jtAsset);
    }

    /**
     * @notice Initializes a kernel where the junior tranche is deployed into Aave V3
     * @param _aaveV3Pool The address of the Aave V3 Pool
     * @param _jtAsset The address of the base asset of the junior tranche
     */
    function __AaveV3_JT_Kernel_init_unchained(address _aaveV3Pool, address _jtAsset) internal onlyInitializing {
        // Ensure that the JT base asset is a supported reserve token in the Aave V3 Pool
        address jtAssetAToken = IPool(_aaveV3Pool).getReserveAToken(_jtAsset);
        require(jtAssetAToken != address(0), UNSUPPORTED_RESERVE_TOKEN());

        // Extend a one time max approval to the Aave V3 pool for the JT's base asset
        IERC20(_jtAsset).forceApprove(_aaveV3Pool, type(uint256).max);

        // Set the initial state of the Aave V3 kernel
        AaveV3JTKernelState storage $ = _getAaveV3JTKernelStorage();
        $.pool = _aaveV3Pool;
        $.poolAddressesProvider = address(IPool(_aaveV3Pool).ADDRESSES_PROVIDER());
        $.jtAssetAToken = jtAssetAToken;
    }

    /// @inheritdoc IRoycoKernel
    function jtPreviewDeposit(TRANCHE_UNIT _assets) external view override onlyJuniorTranche returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt) {
        // Preview the deposit by converting the assets to NAV units and returning the NAV at which the shares will be minted
        valueAllocated = jtConvertTrancheUnitsToNAVUnits(_assets);
        navToMintAt = (_accountant().previewSyncTrancheAccounting(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV())).jtEffectiveNAV;
    }

    /// @inheritdoc IRoycoKernel
    function jtDeposit(
        TRANCHE_UNIT _assets,
        address,
        address
    )
        external
        override(IRoycoKernel)
        onlyJuniorTranche
        whenNotPaused
        returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt)
    {
        // Execute a pre-op sync on accounting
        valueAllocated = jtConvertTrancheUnitsToNAVUnits(_assets);
        navToMintAt = (_preOpSyncTrancheAccounting()).jtEffectiveNAV;

        // Max approval already given to the pool on initialization
        IPool(_getAaveV3JTKernelStorage().pool).supply(RoycoKernelStorageLib._getRoycoKernelStorage().jtAsset, toUint256(_assets), address(this), 0);

        // Execute a post-op sync on accounting
        _postOpSyncTrancheAccounting(Operation.JT_INCREASE_NAV);
    }

    /// @inheritdoc IRoycoKernel
    function jtRedeem(
        uint256 _shares,
        address _controller,
        address _receiver
    )
        external
        override(IRoycoKernel)
        onlyJuniorTranche
        returns (AssetClaims memory userAssetClaims)
    {
        // Execute a pre-op sync on accounting
        SyncedAccountingState memory state;
        uint256 totalTrancheShares;
        (state, userAssetClaims, totalTrancheShares) = _preOpSyncTrancheAccounting(TrancheType.JUNIOR);

        // Ensure that the shares to redeem are actually claimable right now
        require(_shares <= _jtClaimableRedeemRequest(_controller), INSUFFICIENT_CLAIMABLE_SHARES(_shares, _jtClaimableRedeemRequest(_controller)));

        // Get the total NAV to withdraw on this redemption
        NAV_UNIT navOfSharesToRedeem = _processClaimableRedeemRequest(_controller, state.jtEffectiveNAV, _shares, totalTrancheShares);

        // Scale the claims based on the NAV to liquidate for the user relative to the total JT controlled NAV
        userAssetClaims = UtilsLib.scaleTrancheAssetsClaim(userAssetClaims, navOfSharesToRedeem, state.jtEffectiveNAV);

        // Withdraw the asset claims from each tranche and transfer them to the receiver
        _withdrawAssets(userAssetClaims, _receiver);

        // Execute a post-op sync on accounting and enforce the market's coverage requirement
        _postOpSyncTrancheAccountingAndEnforceCoverage(Operation.JT_DECREASE_NAV);
    }

    /// @inheritdoc RoycoKernel
    function _getJuniorTrancheRawNAV() internal view override(RoycoKernel) returns (NAV_UNIT) {
        // The tranche's balance of the AToken is the total assets it is owed from the Aave pool
        /// @dev This does not treat illiquidity in the Aave pool as a loss: we assume that total lent will be withdrawable at some point
        return jtConvertTrancheUnitsToNAVUnits(toTrancheUnits(IERC20(_getAaveV3JTKernelStorage().jtAssetAToken).balanceOf(address(this))));
    }

    /// @inheritdoc RoycoKernel
    function _jtMaxDepositGlobally(address) internal view override(RoycoKernel) returns (TRANCHE_UNIT) {
        // Retrieve the Pool's data provider and asset
        IPoolDataProvider poolDataProvider = IPoolDataProvider(IPoolAddressesProvider(_getAaveV3JTKernelStorage().poolAddressesProvider).getPoolDataProvider());
        address asset = RoycoKernelStorageLib._getRoycoKernelStorage().jtAsset;

        // If the reserve asset is inactive, frozen, or paused, supplies are forbidden
        (uint256 decimals,,,,,,,, bool isActive, bool isFrozen) = poolDataProvider.getReserveConfigurationData(asset);
        if (!isActive || isFrozen || poolDataProvider.getPaused(asset)) return ZERO_TRANCHE_UNITS;

        // Get the supply cap for the reserve asset. If unset, the suppliable amount is unbounded
        (, uint256 supplyCap) = poolDataProvider.getReserveCaps(asset);
        if (supplyCap == 0) return toTrancheUnits(type(uint256).max);

        // Compute the total reserve assets supplied and accrued to the treasury
        (uint256 totalAccruedToTreasury, uint256 totalLent) = _getTotalAccruedToTreasuryAndLent(poolDataProvider, asset);
        uint256 currentlySupplied = totalLent + totalAccruedToTreasury;
        // Supply cap was returned as whole tokens, so we must scale by underlying decimals
        supplyCap = supplyCap * (10 ** decimals);

        // If supply cap hit, no incremental supplies are permitted. Else, return the max suppliable amount within the cap.
        return toTrancheUnits((currentlySupplied >= supplyCap) ? 0 : (supplyCap - currentlySupplied));
    }

    /**
     * @notice Helper function to get the total accrued to treasury and total lent from the pool data provider
     * @dev IPoolDataProvider.getReserveData returns a tuple of 11 words which saturates the stack
     * @dev Uses a low-level static call to the pool data provider to avoid stack too deep errors
     * @param _poolDataProvider The Aave V3 pool data provider
     * @param _asset The asset to get the total lent data for
     * @return totalAccruedToTreasury The total assets accrued to the Aave treasury that exist in the lending pool
     * @return totalLent The total assets lent and owned by lenders of the pool
     */
    function _getTotalAccruedToTreasuryAndLent(
        IPoolDataProvider _poolDataProvider,
        address _asset
    )
        internal
        view
        returns (uint256 totalAccruedToTreasury, uint256 totalLent)
    {
        bytes memory data = abi.encodeCall(IPoolDataProvider.getReserveData, (_asset));
        bool success;
        assembly ("memory-safe") {
            // Load the free memory pointer, and allocate 0x60 bytes for the return data
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, 0x60))

            // Make the static call to the pool data provider
            success := staticcall(gas(), _poolDataProvider, add(data, 0x20), mload(data), ptr, 0x60)

            // Load the total accrued to treasury and total lent from the return data
            // Refer IPoolDataProvider.getReserveData for the return data layout
            totalAccruedToTreasury := mload(add(ptr, 0x20))
            totalLent := mload(add(ptr, 0x40))
        }
        require(success, FAILED_CALL());
    }

    /// @inheritdoc RoycoKernel
    function _jtMaxWithdrawableGlobally(address) internal view override(RoycoKernel) returns (TRANCHE_UNIT) {
        // Retrieve the Pool's data provider and asset
        AaveV3JTKernelState storage $ = _getAaveV3JTKernelStorage();
        IPoolDataProvider poolDataProvider = IPoolDataProvider(IPoolAddressesProvider($.poolAddressesProvider).getPoolDataProvider());
        address asset = RoycoKernelStorageLib._getRoycoKernelStorage().jtAsset;

        // If the reserve asset is inactive or paused, withdrawals are forbidden
        (,,,,,,,, bool isActive,) = poolDataProvider.getReserveConfigurationData(asset);
        if (!isActive || poolDataProvider.getPaused(asset)) return ZERO_TRANCHE_UNITS;

        // Return the unborrowed/reserve assets of the pool
        return toTrancheUnits(IERC20(asset).balanceOf($.jtAssetAToken));
    }

    /// @inheritdoc RoycoKernel
    function _previewWithdrawJTAssets(TRANCHE_UNIT _jtAssets) internal view override(RoycoKernel) returns (TRANCHE_UNIT redeemedJTAssets) {
        // TODO: Do we want to bound this to max withdrawable?
        return _jtAssets;
    }

    /// @inheritdoc RoycoKernel
    function _jtWithdrawAssets(TRANCHE_UNIT _jtAssets, address _receiver) internal override(RoycoKernel) {
        IPool(_getAaveV3JTKernelStorage().pool).withdraw(RoycoKernelStorageLib._getRoycoKernelStorage().jtAsset, toUint256(_jtAssets), _receiver);
    }

    /**
     * @notice Returns a storage pointer to the AaveV3JTKernelState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer to the Aave V3 JT kernel state
     */
    function _getAaveV3JTKernelStorage() internal pure returns (AaveV3JTKernelState storage $) {
        assembly ("memory-safe") {
            $.slot := AAVE_V3_JT_KERNEL_STORAGE_SLOT
        }
    }
}
