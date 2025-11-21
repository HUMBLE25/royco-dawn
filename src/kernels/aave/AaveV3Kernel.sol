// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IPool, IPoolAddressesProvider } from "../../../lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { IPoolDataProvider } from "../../../lib/aave-v3-origin/src/contracts/interfaces/IPoolDataProvider.sol";
import { Initializable } from "../../../lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import { IERC20, SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ExecutionModel, IBaseKernel } from "../../interfaces/kernel/IBaseKernel.sol";
import { BaseKernel } from "../base/BaseKernel.sol";

/**
 * @title AaveV3Kernel
 * @notice Kernel implementation for Aave V3
 * @dev Handles asset management operations for the Aave V3 lending pool
 */
contract AaveV3Kernel is Initializable, BaseKernel {
    using SafeERC20 for IERC20;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant override DEPOSIT_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant override WITHDRAWAL_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IBaseKernel
    bool public constant override SUPPORTS_DEPOSIT_CANCELLATION = false;

    /// @inheritdoc IBaseKernel
    bool public constant override SUPPORTS_REDEMPTION_CANCELLATION = false;

    /// @notice The Aave V3 Pool deployment
    IPool public immutable POOL;

    /// @notice The Aave V3 Pool Addresses Provider for accessing periphery contracts
    IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;

    /**
     * @notice Initializes the Aave V3 Kernel implementation with the specified Aave V3 Pool
     * @param _pool The Aave V3 Pool contract address
     */
    constructor(IPool _pool) {
        POOL = _pool;
        POOL_ADDRESSES_PROVIDER = POOL.ADDRESSES_PROVIDER();
    }

    /**
     * @notice Initializes a Royco tranche using the Aave V3 Kernel
     * Must be called via delegatecall to effectuate the max approval in the context of the Royco Tranche
     * @param _asset The base asset of the Royco tranche
     */
    function initialize(address _asset) external initializer onlyDelegateCall {
        // TODO: Some tokens will revert here. Maybe type(uint96).max is sufficient.
        IERC20(_asset).forceApprove(address(POOL), type(uint256).max);
    }

    /// @inheritdoc IBaseKernel
    function getNAV(address _asset) external view override returns (uint256) {
        // The tranche's balance of the AToken is the total assets it can withdraw from Aave
        // In addition to any assets already in the tranche (in the case of a force withdrawal)
        return IERC20(POOL.getReserveAToken(_asset)).balanceOf(msg.sender) + IERC20(_asset).balanceOf(msg.sender);
    }

    /// @inheritdoc IBaseKernel
    /// @dev Ignore the receiver parameter as deposits aren't discriminated by address
    function maxDeposit(address, address _asset) external view override returns (uint256) {
        // Retrieve the Pool data provider
        IPoolDataProvider poolDataProvider = IPoolDataProvider(POOL_ADDRESSES_PROVIDER.getPoolDataProvider());

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
        if (currentlySupplied >= supplyCap) return 0;
        else return supplyCap - currentlySupplied;
    }

    /// @inheritdoc IBaseKernel
    /// @dev Ignore the owner parameter as withdrawals aren't discriminated by address
    function maxWithdraw(address, address _asset) external view override returns (uint256) {
        // Retrieve the Pool data provider
        IPoolDataProvider poolDataProvider = IPoolDataProvider(POOL_ADDRESSES_PROVIDER.getPoolDataProvider());

        // If the reserve asset is inactive or paused, withdrawals are forbidden
        (,,,,,,,, bool isActive,) = poolDataProvider.getReserveConfigurationData(_asset);
        if (!isActive || poolDataProvider.getPaused(_asset)) return 0;

        // Return the total idle/unborrowed reserve assets. This is the max that can be withdrawn from the Pool.
        return IERC20(_asset).balanceOf((POOL).getReserveAToken(_asset));
    }

    /// @inheritdoc IBaseKernel
    /// @dev Ignore the controller param since this kernel employs the synchronous deposit flow
    function deposit(address _asset, uint256 _assets, address) external override onlyDelegateCall {
        // Max approval given to the pool on initialization
        POOL.supply(_asset, _assets, address(this), 0);
    }

    /// @inheritdoc IBaseKernel
    /// @dev Ignore the controller param since this kernel employs the synchronous withdrawal flow
    function withdraw(address _asset, uint256 _assets, address, address _receiver) external override onlyDelegateCall {
        // Retrieve the liquid reserves of the tranche
        uint256 trancheReserves = IERC20(_asset).balanceOf(address(this));
        // If any liquid reserves exist
        if (trancheReserves > 0) {
            // If the reserves can service the entire withdrawal, do so, and preemptively return
            if (trancheReserves >= _assets) return IERC20(_asset).safeTransfer(_receiver, _assets);
            // Else, service as much of the withdrawal as possible
            else IERC20(_asset).safeTransfer(_receiver, trancheReserves);
        }

        // Only withdraw the assets that are still owed to the receiver
        POOL.withdraw(_asset, (_assets - trancheReserves), _receiver);
    }
}
