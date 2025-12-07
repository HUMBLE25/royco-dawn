// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPool } from "../../../interfaces/aave/IPool.sol";
import { IPoolAddressesProvider } from "../../../interfaces/aave/IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "../../../interfaces/aave/IPoolDataProvider.sol";
import { BaseKernelState, BaseKernelStorageLib } from "../../../libraries/BaseKernelStorageLib.sol";
import { AaveV3KernelState, AaveV3KernelStorageLib } from "../../../libraries/kernels/AaveV3KernelStorageLib.sol";
import { BaseKernel, IBaseKernel } from "../BaseKernel.sol";

abstract contract AaveV3JTKernel is BaseKernel {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes a kernel where the junior tranche is deployed into Aave V3
     * @dev Mandates that the base kernel state is already initialized
     * @param _aaveV3Pool The address of the Aave V3 Pool
     */
    function __AaveV3JTKernel_init_unchained(IPool _aaveV3Pool) internal onlyInitializing {
        // Initialize the Aave V3 kernel storage
        AaveV3KernelStorageLib.__AaveV3Kernel_init(address(_aaveV3Pool), address(_aaveV3Pool.ADDRESSES_PROVIDER()));

        // Extend a one time max approval to the Aave V3 pool
        address jtAsset = IERC4626(BaseKernelStorageLib._getBaseKernelStorage().juniorTranche).asset();
        IERC20(jtAsset).forceApprove(address(_aaveV3Pool), type(uint256).max);
    }

    /// @inheritdoc IBaseKernel
    function jtMaxDeposit(address _asset, address) external view override(IBaseKernel) returns (uint256) {
        IPoolDataProvider poolDataProvider =
            IPoolDataProvider(IPoolAddressesProvider(AaveV3KernelStorageLib._getAaveV3KernelStorage().poolAddressesProvider).getPoolDataProvider());

        // If the reserve asset is inactive, frozen, or paused, supplies are forbidden
        (uint256 decimals,,,,,,,, bool isActive, bool isFrozen) = poolDataProvider.getReserveConfigurationData(_asset);
        if (!isActive || isFrozen || poolDataProvider.getPaused(_asset)) return 0;

        // Get the supply cap for the reserve asset. If unset, the suppliable amount is unbounded
        (, uint256 supplyCap) = poolDataProvider.getReserveCaps(_asset);
        if (supplyCap == 0) return type(uint256).max;

        // Compute the total reserve assets supplied and accrued to the treasury
        (, uint256 totalAccruedToTreasury, uint256 totalLent,,,,,,,,,) = poolDataProvider.getReserveData(_asset);
        uint256 currentlySupplied = totalLent + totalAccruedToTreasury;
        // Supply cap was returned as whole tokens, so we must scale by underlying decimals
        supplyCap = supplyCap * (10 ** decimals);

        // If supply cap hit, no incremental supplies are permitted. Else, return the max suppliable amount within the cap.
        return (currentlySupplied >= supplyCap) ? 0 : (supplyCap - currentlySupplied);
    }

    /// @inheritdoc IBaseKernel
    function jtMaxWithdraw(address _asset, address) external view override(IBaseKernel) returns (uint256) {
        AaveV3KernelState storage $ = AaveV3KernelStorageLib._getAaveV3KernelStorage();

        IPoolDataProvider poolDataProvider = IPoolDataProvider(IPoolAddressesProvider($.poolAddressesProvider).getPoolDataProvider());

        // If the reserve asset is inactive or paused, withdrawals are forbidden
        (,,,,,,,, bool isActive,) = poolDataProvider.getReserveConfigurationData(_asset);
        if (!isActive || poolDataProvider.getPaused(_asset)) return 0;

        // Return the total idle/unborrowed reserve assets. This is the max that can be withdrawn from the Pool.
        return IERC20(_asset).balanceOf(IPool($.pool).getReserveAToken(_asset));
    }

    /// @inheritdoc IBaseKernel
    function jtDeposit(
        address _asset,
        uint256 _assets,
        address,
        address
    )
        external
        override(IBaseKernel)
        onlyJuniorTranche
        returns (uint256 fractionOfTotalAssetsAllocatedWAD)
    {
        // Max approval given to the pool on initialization
        IPool(AaveV3KernelStorageLib._getAaveV3KernelStorage().pool).supply(_asset, _assets, address(this), 0);
    }

    /// @inheritdoc IBaseKernel
    function jtWithdraw(
        address _asset,
        uint256 _assets,
        address,
        address _receiver
    )
        external
        override(IBaseKernel)
        onlyJuniorTranche
        returns (uint256 fractionOfTotalAssetsRedeemedWAD, uint256 assetsRedeemed)
    {
        // Only withdraw the assets that are still owed to the receiver
        IPool(AaveV3KernelStorageLib._getAaveV3KernelStorage().pool).withdraw(_asset, _assets, _receiver);
    }
}
