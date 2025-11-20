// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAsyncDepositKernel } from "../interfaces/kernel/IAsyncDepositKernel.sol";
import { IAsyncWithdrawalKernel } from "../interfaces/kernel/IAsyncWithdrawalKernel.sol";
import { ActionType, IBaseKernel } from "../interfaces/kernel/IBaseKernel.sol";
import { ICancellableKernel } from "../interfaces/kernel/ICancellableKernel.sol";

/**
 * @title RoycoKernelLib
 * @notice Library for interacting with Royco kernel contracts
 * @dev Provides a standardized interface for kernel interactions with proper error handling
 */
library RoycoKernelLib {
    /**
     * @notice Thrown when a kernel delegate call fails
     * @param callData The calldata of the delegatecall that failed
     * @param returnData The return data from the failed delegatecall
     */
    error KERNEL_DELEGATECALL_FAILED(bytes callData, bytes returnData);

    /**
     * @notice Initializes the kernel with provided parameters
     * @param _kernel The address of the kernel contract
     * @param _initCallData The initialization calldata to pass to the kernel
     */
    function __Kernel_init(address _kernel, bytes calldata _initCallData) internal {
        // Premptively return if the kernel doesn't require initialization
        if (_initCallData.length == 0) return;
        _delegateCallKernel(_kernel, _initCallData);
    }

    // =============================
    // Core Asset Management
    // =============================

    /**
     * @notice Gets the total assets controlled by this tranche via the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @return The total amount of assets (NAV) of this Royco tranche
     */
    function _totalAssets(address _kernel, address _asset) internal view returns (uint256) {
        return IBaseKernel(_kernel).totalAssets(_asset);
    }

    /**
     * @notice Gets the maximum deposit amount for a specific asset
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @return The maximum assets depositable into this Royco tranche
     */
    function _maxDeposit(address _kernel, address _asset) internal view returns (uint256) {
        return IBaseKernel(_kernel).maxDeposit(address(this), address(this), _asset);
    }

    /**
     * @notice Gets the maximum withdrawal amount for a specific asset
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @return The maximum assets withdrawable from this Royco tranche
     */
    function _maxWithdraw(address _kernel, address _asset) internal view returns (uint256) {
        return IBaseKernel(_kernel).maxWithdraw(address(this), address(this), _asset);
    }

    // =============================
    // Kernel Configuration
    // =============================

    /**
     * @notice Gets the deposit action type constant from the kernel
     * @param _kernel The address of the kernel contract
     * @return The execution semantics of depositing into this tranche (SYNC or ASYNC)
     */
    function _DEPOSIT_TYPE(address _kernel) internal pure returns (ActionType) {
        return IBaseKernel(_kernel).DEPOSIT_TYPE();
    }

    /**
     * @notice Gets the withdrawal action type constant from the kernel
     * @param _kernel The address of the kernel contract
     * @return The execution semantics of withdrawing from this tranche (SYNC or ASYNC)
     */
    function _WITHDRAW_TYPE(address _kernel) internal pure returns (ActionType) {
        return IBaseKernel(_kernel).WITHDRAW_TYPE();
    }

    /**
     * @notice Checks if the kernel supports deposit cancellation
     * @param _kernel The address of the kernel contract
     * @return True if deposit cancellation is supported
     */
    function _SUPPORTS_DEPOSIT_CANCELLATION(address _kernel) internal pure returns (bool) {
        return IBaseKernel(_kernel).SUPPORTS_DEPOSIT_CANCELLATION();
    }

    /**
     * @notice Checks if the kernel supports redemption cancellation
     * @param _kernel The address of the kernel contract
     * @return True if redemption cancellation is supported
     */
    function _SUPPORTS_REDEMPTION_CANCELLATION(address _kernel) internal pure returns (bool) {
        return IBaseKernel(_kernel).SUPPORTS_REDEMPTION_CANCELLATION();
    }

    // =============================
    // Synchronous Operations
    // =============================

    /**
     * @notice Executes a deposit to the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to deposit
     * @param _assets The amount of assets to deposit
     * @param _controller The address of the controller
     */
    function _deposit(address _kernel, address _asset, uint256 _assets, address _controller) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IBaseKernel.deposit, (_asset, _assets, _controller)));
    }

    /**
     * @notice Executes a withdrawal from the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to withdraw
     * @param _assets The amount to withdraw
     * @param _controller The address of the controller
     * @param _receiver The address to receive the withdrawn assets
     */
    function _withdraw(address _kernel, address _asset, uint256 _assets, address _controller, address _receiver) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IBaseKernel.withdraw, (_asset, _assets, _controller, _receiver)));
    }

    // =============================
    // Asynchronous Deposit Operations
    // =============================

    /**
     * @notice Requests a deposit to the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to deposit
     * @param _assets The amount of assets to deposit
     * @param _controller The address of the controller
     * @return requestId The request ID of this deposit request
     */
    function _requestDeposit(address _kernel, address _asset, uint256 _assets, address _controller) internal returns (uint256 requestId) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IAsyncDepositKernel.requestDeposit, (_asset, _assets, _controller)));
        return abi.decode(returnData, (uint256));
    }

    /**
     * @notice Gets the pending deposit request amount
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this deposit request
     * @param _controller The address of the controller
     * @return pendingAssets The amount of assets pending deposit in the request
     */
    function _pendingDepositRequest(address _kernel, uint256 _requestId, address _controller) internal returns (uint256 pendingAssets) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(IAsyncDepositKernel.pendingDepositRequest, (_requestId, _controller))), (uint256));
    }

    /**
     * @notice Gets the claimable deposit request amount
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this deposit request
     * @param _controller The address of the controller
     * @return claimableAssets The amount of assets claimable from completed deposit requests
     */
    function _claimableDepositRequest(address _kernel, uint256 _requestId, address _controller) internal returns (uint256 claimableAssets) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(IAsyncDepositKernel.claimableDepositRequest, (_requestId, _controller))), (uint256));
    }

    // =============================
    // Asynchronous Withdrawal Operations
    // =============================

    /**
     * @notice Requests a withdrawal from the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to withdraw
     * @param _expectedAssets The expected amount of assets to receive for the shares redeemed
     * @param _shares The amount of shares being requested to be redeemed
     * @param _controller The address of the controller
     * @return requestId The request ID of this withdrawal request
     */
    function _requestRedeem(
        address _kernel,
        address _asset,
        uint256 _expectedAssets,
        uint256 _shares,
        address _controller
    )
        internal
        returns (uint256 requestId)
    {
        return abi.decode(
            _delegateCallKernel(_kernel, abi.encodeCall(IAsyncWithdrawalKernel.requestRedeem, (_asset, _expectedAssets, _shares, _controller))), (uint256)
        );
    }

    /**
     * @notice Gets the pending redeem request amount
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The address of the controller
     * @return pendingShares The amount of shares pending redemption in the request
     */
    function _pendingRedeemRequest(address _kernel, uint256 _requestId, address _controller) internal returns (uint256 pendingShares) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(IAsyncWithdrawalKernel.pendingRedeemRequest, (_requestId, _controller))), (uint256));
    }

    /**
     * @notice Gets the claimable redeem request amount
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The address of the controller
     * @return claimableShares The amount of shares claimable from completed redemption requests
     */
    function _claimableRedeemRequest(address _kernel, uint256 _requestId, address _controller) internal returns (uint256 claimableShares) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(IAsyncWithdrawalKernel.pendingRedeemRequest, (_requestId, _controller))), (uint256));
    }

    // =============================
    // Cancellation Operations
    // =============================

    /**
     * @notice Cancels a deposit request
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this deposit request
     * @param _controller The address of the controller
     */
    function _cancelDepositRequest(address _kernel, uint256 _requestId, address _controller) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(ICancellableKernel.cancelDepositRequest, (_requestId, _controller)));
    }

    /**
     * @notice Checks if a deposit cancellation request is pending
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this deposit request
     * @param _controller The address of the controller
     * @return isPending True if cancellation request is pending
     */
    function _pendingCancelDepositRequest(address _kernel, uint256 _requestId, address _controller) internal returns (bool isPending) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(ICancellableKernel.pendingCancelDepositRequest, (_requestId, _controller))), (bool));
    }

    /**
     * @notice Gets the claimable amount from a deposit cancellation request
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this deposit request
     * @param _controller The address of the controller
     * @return assets The amount of assets claimable from the deposit cancellation
     */
    function _claimableCancelDepositRequest(address _kernel, uint256 _requestId, address _controller) internal returns (uint256 assets) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(ICancellableKernel.claimableCancelDepositRequest, (_requestId, _controller))), (uint256));
    }

    /**
     * @notice Cancels a redeem request
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The address of the controller
     */
    function _cancelRedeemRequest(address _kernel, uint256 _requestId, address _controller) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(ICancellableKernel.cancelRedeemRequest, (_requestId, _controller)));
    }

    /**
     * @notice Checks if a redeem cancellation request is pending
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The address of the controller
     * @return isPending True if cancellation request is pending
     */
    function _pendingCancelRedeemRequest(address _kernel, uint256 _requestId, address _controller) internal returns (bool isPending) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(ICancellableKernel.pendingCancelRedeemRequest, (_requestId, _controller))), (bool));
    }

    /**
     * @notice Gets the claimable amount from a redeem cancellation request
     * @param _kernel The address of the kernel contract
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The address of the controller
     * @return shares The amount of shares claimable from the redeem cancellation
     */
    function _claimableCancelRedeemRequest(address _kernel, uint256 _requestId, address _controller) internal returns (uint256 shares) {
        return abi.decode(_delegateCallKernel(_kernel, abi.encodeCall(ICancellableKernel.claimableCancelRedeemRequest, (_requestId, _controller))), (uint256));
    }

    // =============================
    // Internal Helper Functions
    // =============================

    /**
     * @notice Executes a delegate call to the kernel with error handling
     * @param _kernel The address of the kernel contract
     * @param _callData The encoded function call data
     * @return The return data from the delegate call
     */
    function _delegateCallKernel(address _kernel, bytes memory _callData) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = _kernel.delegatecall(_callData);
        if (!success) {
            if (returnData.length == 0) revert KERNEL_DELEGATECALL_FAILED(_callData, returnData);
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }
        return returnData;
    }
}
