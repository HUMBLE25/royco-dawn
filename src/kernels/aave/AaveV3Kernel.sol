// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IPool, IPoolAddressesProvider } from "../../../lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { IPoolDataProvider } from "../../../lib/aave-v3-origin/src/contracts/interfaces/IPoolDataProvider.sol";
import { IERC20, SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRoycoVaultKernel } from "../../interfaces/IRoycoVaultKernel.sol";
import { BaseKernel } from "../base/BaseKernel.sol";

/**
 * @title AaveV3Kernel
 * @notice Kernel implementation for Aave V3
 * @dev Handles asset management operations for the Aave V3 lending pool
 */
contract AaveV3Kernel is BaseKernel {
    using SafeERC20 for IERC20;

    /// @inheritdoc IRoycoVaultKernel
    ActionType public constant override DEPOSIT_TYPE = ActionType.SYNC;

    /// @inheritdoc IRoycoVaultKernel
    ActionType public constant override WITHDRAW_TYPE = ActionType.SYNC;

    /// @inheritdoc IRoycoVaultKernel
    bool public constant override SUPPORTS_DEPOSIT_CANCELLATION = false;

    /// @inheritdoc IRoycoVaultKernel
    bool public constant override SUPPORTS_REDEMPTION_CANCELLATION = false;

    /// @notice The Aave V3 Pool deployment
    IPool public immutable POOL;

    /// @notice The Aave V3 Pool Addresses Provider for accessing periphery contracts
    IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;

    /**
     * @notice Initializes the Aave V3 Kernel with the specified Aave V3 Pool
     * @param _pool The Aave V3 Pool contract address
     */
    constructor(IPool _pool) {
        POOL = _pool;
        POOL_ADDRESSES_PROVIDER = POOL.ADDRESSES_PROVIDER();
    }

    /// @inheritdoc IRoycoVaultKernel
    function totalAssets(address _asset) external view override returns (uint256) {
        // The caller's balance of the AToken is the total assets they can withdraw from the underlying protocol
        return IERC20(POOL.getReserveAToken(_asset)).balanceOf(msg.sender);
    }

    /// @inheritdoc IRoycoVaultKernel
    function maxDeposit(address _asset) external view override returns (uint256) {
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

    /// @inheritdoc IRoycoVaultKernel
    function maxWithdraw(address _asset) external view override returns (uint256) {
        // Retrieve the Pool data provider
        IPoolDataProvider poolDataProvider = IPoolDataProvider(POOL_ADDRESSES_PROVIDER.getPoolDataProvider());

        // If the reserve asset is inactive or paused, withdrawals are forbidden
        (,,,,,,,, bool isActive,) = poolDataProvider.getReserveConfigurationData(_asset);
        if (!isActive || poolDataProvider.getPaused(_asset)) return 0;

        // Return the total idle/unborrowed reserve assets. This is the max that can be withdrawn from the Pool.
        return IERC20(_asset).balanceOf((POOL).getReserveAToken(_asset));
    }

    /// @inheritdoc IRoycoVaultKernel
    function deposit(address _asset, address, uint256 _amount) external override onlyDelegateCall {
        IERC20(_asset).forceApprove(address(POOL), _amount);
        POOL.supply(_asset, _amount, address(this), 0);
    }

    /// @inheritdoc IRoycoVaultKernel
    function withdraw(address _asset, address, uint256 _amount, address _recipient) external override onlyDelegateCall {
        POOL.withdraw(_asset, _amount, _recipient);
    }

    /// @inheritdoc IRoycoVaultKernel
    function requestDeposit(address, address, uint256) external view override disabled { }

    /// @inheritdoc IRoycoVaultKernel
    function pendingDepositRequest(address, address) external view override disabled returns (uint256) { }

    /// @inheritdoc IRoycoVaultKernel
    function claimableDepositRequest(address, address) external view override disabled returns (uint256) { }

    /// @inheritdoc IRoycoVaultKernel
    function requestWithdraw(address, address, uint256) external view override disabled { }

    /// @inheritdoc IRoycoVaultKernel
    function pendingRedeemRequest(address, address) external pure override disabled returns (uint256) { }

    /// @inheritdoc IRoycoVaultKernel
    function claimableRedeemRequest(address, address) external pure override disabled returns (uint256) { }

    /// @inheritdoc IRoycoVaultKernel
    function cancelDepositRequest(address _controller) external disabled { }

    /// @inheritdoc IRoycoVaultKernel
    function cancelRedeemRequest(address _controller) external disabled { }

    /// @inheritdoc IRoycoVaultKernel
    function claimableCancelDepositRequest(address _asset, address _controller) external view disabled returns (uint256 assets) { }

    /// @inheritdoc IRoycoVaultKernel
    function claimableCancelRedeemRequest(address _asset, address _controller) external view disabled returns (uint256 shares) { }

    /// @inheritdoc IRoycoVaultKernel
    function pendingCancelDepositRequest(address _asset, address _controller) external view disabled returns (bool isPending) { }

    /// @inheritdoc IRoycoVaultKernel
    function pendingCancelRedeemRequest(address _asset, address _controller) external view disabled returns (bool isPending) { }
}
