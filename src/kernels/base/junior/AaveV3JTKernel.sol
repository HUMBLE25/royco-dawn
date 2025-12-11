// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IPool } from "../../../interfaces/aave/IPool.sol";
import { IPoolAddressesProvider } from "../../../interfaces/aave/IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "../../../interfaces/aave/IPoolDataProvider.sol";
import { ExecutionModel, IBaseKernel } from "../../../interfaces/kernel/IBaseKernel.sol";
import { BaseKernelState, BaseKernelStorageLib, Operation } from "../../../libraries/BaseKernelStorageLib.sol";

import { BaseKernelStorageLib } from "../../../libraries/BaseKernelStorageLib.sol";
import { ConstantsLib } from "../../../libraries/ConstantsLib.sol";
import { AaveV3KernelState, AaveV3KernelStorageLib } from "../../../libraries/kernels/AaveV3KernelStorageLib.sol";
import { BaseKernel } from "../BaseKernel.sol";
import { BaseAsyncJTWithrawalDelayKernel } from "./BaseAsyncJTWithrawalDelayKernel.sol";

abstract contract AaveV3JTKernel is BaseKernel, BaseAsyncJTWithrawalDelayKernel {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant JT_DEPOSIT_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant JT_WITHDRAWAL_EXECUTION_MODEL = ExecutionModel.ASYNC;

    /**
     * @notice Initializes a kernel where the junior tranche is deployed into Aave V3
     * @dev Mandates that the base kernel state is already initialized
     * @param _aaveV3Pool The address of the Aave V3 Pool
     */
    function __AaveV3JTKernel_init_unchained(address _aaveV3Pool) internal onlyInitializing {
        // Extend a one time max approval to the Aave V3 pool for the JT's base asset
        address jtAsset = IERC4626(BaseKernelStorageLib._getBaseKernelStorage().juniorTranche).asset();
        IERC20(jtAsset).forceApprove(_aaveV3Pool, type(uint256).max);

        // Initialize the Aave V3 kernel storage
        AaveV3KernelStorageLib.__AaveV3Kernel_init(
            _aaveV3Pool, address(IPool(_aaveV3Pool).ADDRESSES_PROVIDER()), jtAsset, IPool(_aaveV3Pool).getReserveAToken(jtAsset)
        );
    }

    /// @inheritdoc IBaseKernel
    function getJTTotalEffectiveAssets() public view override(IBaseKernel, BaseAsyncJTWithrawalDelayKernel) returns (uint256) {
        return _getJuniorTrancheEffectiveNAV();
    }

    /// @inheritdoc IBaseKernel
    function jtDeposit(
        address,
        uint256 _assets,
        address,
        address
    )
        external
        override(IBaseKernel)
        onlyJuniorTranche
        syncNAVs(Operation.JT_DEPOSIT)
        whenNotPaused
        returns (uint256 underlyingSharesAllocated, uint256 totalUnderlyingShares)
    {
        // Max approval already given to the pool on initialization
        AaveV3KernelState storage $ = AaveV3KernelStorageLib._getAaveV3KernelStorage();
        IPool($.pool).supply($.asset, _assets, address(this), 0);
        underlyingSharesAllocated = _assets;
        totalUnderlyingShares = _getJuniorTrancheEffectiveNAV();
    }

    /// @inheritdoc IBaseKernel
    function jtRedeem(
        address _asset,
        uint256 _shares,
        uint256 _totalShares,
        address _controller,
        address _receiver
    )
        external
        override(IBaseKernel)
        onlyJuniorTranche
        syncNAVsAndEnforceCoverage(Operation.JT_WITHDRAW)
        returns (uint256 assetsWithdrawn)
    {
        _processClaimableRedeemRequest(_controller, _shares);
        // Get the storage pointer to the base kernel state
        // We can assume that all NAV values are synced
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();
        uint256 jtEffectiveNAV = $.lastJTEffectiveNAV;
        // Compute the assets expected to be received on withdrawal based on the JT's effective NAV
        uint256 assetsToWithdraw = _shares.mulDiv(jtEffectiveNAV, _totalShares, Math.Rounding.Floor);
        // Compute the yield that has accrued in ST that JT is entitled to
        uint256 jtShareOfSTYield = Math.saturatingSub(jtEffectiveNAV, $.lastJTRawNAV);
        // Pull any yield that needs to be realized from ST
        if (jtShareOfSTYield != 0) {
            uint256 yieldToClaim = _shares.mulDiv(jtShareOfSTYield, _totalShares, Math.Rounding.Floor);
            assetsToWithdraw -= (assetsWithdrawn += _claimJTYieldFromST(_asset, yieldToClaim, _receiver));
        }
        assetsWithdrawn += _withdrawFromPool(assetsToWithdraw, _receiver);
        // TODO: Should we check assetsWithdrawn == totalAssetsToWithdraw. Considering rounding in the underlying scenario.
    }

    /// @inheritdoc BaseKernel
    function _coverSTLossesFromJT(address, uint256 _coverageAssets, address _receiver) internal override(BaseKernel) returns (uint256 assetsWithdrawn) {
        return _withdrawFromPool(_coverageAssets, _receiver);
    }

    /**
     * @notice Withdraws the specified assets from the Aave V3 Pool to the receiver
     * @param _assets The amount of assets to withdraw from the pool
     * @param _receiver The receiver of the withdrawn assets
     * @param assetsWithdrawn The actual number of assets withdrawn based on max withdrawal limits
     */
    function _withdrawFromPool(uint256 _assets, address _receiver) internal returns (uint256 assetsWithdrawn) {
        AaveV3KernelState storage $ = AaveV3KernelStorageLib._getAaveV3KernelStorage();
        uint256 maxJTAssetsWithdrawable = _maxJTWithdrawalGlobally(address(0));
        assetsWithdrawn = maxJTAssetsWithdrawable >= _assets ? _assets : maxJTAssetsWithdrawable;
        IPool($.pool).withdraw($.asset, assetsWithdrawn, _receiver);
    }

    /// @inheritdoc BaseKernel
    function _getJuniorTrancheRawNAV() internal view override(BaseKernel) returns (uint256) {
        // The tranche's balance of the AToken is the total assets it is owed from the Aave pool
        /// @dev This does not treat illiquidity in the Aave pool as a loss: we assume that total lent will be withdrawable at some point
        AaveV3KernelState storage $ = AaveV3KernelStorageLib._getAaveV3KernelStorage();
        return IERC20($.aToken).balanceOf(address(this));
    }

    /// @inheritdoc BaseKernel
    function _maxJTDepositGlobally(address) internal view override(BaseKernel) returns (uint256) {
        // Retrieve the Pool's data provider and asset
        AaveV3KernelState storage $ = AaveV3KernelStorageLib._getAaveV3KernelStorage();
        IPoolDataProvider poolDataProvider = IPoolDataProvider(IPoolAddressesProvider($.poolAddressesProvider).getPoolDataProvider());
        address asset = $.asset;

        // If the reserve asset is inactive, frozen, or paused, supplies are forbidden
        (uint256 decimals,,,,,,,, bool isActive, bool isFrozen) = poolDataProvider.getReserveConfigurationData(asset);
        if (!isActive || isFrozen || poolDataProvider.getPaused(asset)) return 0;

        // Get the supply cap for the reserve asset. If unset, the suppliable amount is unbounded
        (, uint256 supplyCap) = poolDataProvider.getReserveCaps(asset);
        if (supplyCap == 0) return type(uint256).max;

        // Compute the total reserve assets supplied and accrued to the treasury
        (, uint256 totalAccruedToTreasury, uint256 totalLent,,,,,,,,,) = poolDataProvider.getReserveData(asset);
        uint256 currentlySupplied = totalLent + totalAccruedToTreasury;
        // Supply cap was returned as whole tokens, so we must scale by underlying decimals
        supplyCap = supplyCap * (10 ** decimals);

        // If supply cap hit, no incremental supplies are permitted. Else, return the max suppliable amount within the cap.
        return (currentlySupplied >= supplyCap) ? 0 : (supplyCap - currentlySupplied);
    }

    /// @inheritdoc BaseKernel
    function _maxJTWithdrawalGlobally(address) internal view override(BaseKernel) returns (uint256) {
        // Retrieve the Pool's data provider and asset
        AaveV3KernelState storage $ = AaveV3KernelStorageLib._getAaveV3KernelStorage();
        IPoolDataProvider poolDataProvider = IPoolDataProvider(IPoolAddressesProvider($.poolAddressesProvider).getPoolDataProvider());
        address asset = $.asset;

        // If the reserve asset is inactive or paused, withdrawals are forbidden
        (,,,,,,,, bool isActive,) = poolDataProvider.getReserveConfigurationData(asset);
        if (!isActive || poolDataProvider.getPaused(asset)) return 0;

        // Return the minimum of the assets lent by the JT and the total idle/unborrowed reserve assets (currently withdrawable from the pool)
        return Math.min(_getJuniorTrancheRawNAV(), IERC20(asset).balanceOf($.aToken));
    }
}
