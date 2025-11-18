// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoKernel } from "../interfaces/IRoycoKernel.sol";

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
     * @param _params The initialization parameters to pass to the kernel
     */
    function __Kernel_init(address _kernel, bytes calldata _params) internal {
        _delegateCallKernel(_kernel, _params);
    }

    /**
     * @notice Gets the total assets controlled by this tranche via the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @return The total amount of assets (NAV) of this Royco tranche
     */
    function _totalAssets(address _kernel, address _asset) internal view returns (uint256) {
        return IRoycoKernel(_kernel).totalAssets(_asset);
    }

    /**
     * @notice Gets the maximum deposit amount for a specific asset
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @return The maximum assets depositable into this Royco tranche
     */
    function _maxDeposit(address _kernel, address _asset) internal view returns (uint256) {
        return IRoycoKernel(_kernel).maxDeposit(_asset);
    }

    /**
     * @notice Gets the maximum withdrawal amount for a specific asset
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @return The maximum assets withdrawable from this Royco tranche
     */
    function _maxWithdraw(address _kernel, address _asset) internal view returns (uint256) {
        return IRoycoKernel(_kernel).maxWithdraw(_asset);
    }

    /**
     * @notice Gets the deposit action type constant from the kernel
     * @param _kernel The address of the kernel contract
     * @return The execution semantics of depositing into this tranche (SYNC or ASYNC)
     */
    function _DEPOSIT_TYPE(address _kernel) internal pure returns (IRoycoKernel.ActionType) {
        return IRoycoKernel(_kernel).DEPOSIT_TYPE();
    }

    /**
     * @notice Gets the withdrawal action type constant from the kernel
     * @param _kernel The address of the kernel contract
     * @return The execution semantics of withdrawing from this tranche (SYNC or ASYNC)
     */
    function _WITHDRAW_TYPE(address _kernel) internal pure returns (IRoycoKernel.ActionType) {
        return IRoycoKernel(_kernel).WITHDRAW_TYPE();
    }

    /**
     * @notice Requests a deposit to the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to deposit
     * @param _controller The address of the controller
     * @param _amount The amount of assets to deposit
     */
    function _requestDeposit(address _kernel, address _asset, address _controller, uint256 _amount) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.requestDeposit, (_asset, _controller, _amount)));
    }

    /**
     * @notice Gets the pending deposit request amount
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return pendingAssets The amount of assets pending deposit in the request
     */
    function _pendingDepositRequest(address _kernel, address _asset, address _controller) internal returns (uint256 pendingAssets) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.pendingDepositRequest, (_asset, _controller)));
        return abi.decode(returnData, (uint256));
    }

    /**
     * @notice Gets the claimable deposit request amount
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return claimableAssets The amount of assets depositable in the request
     */
    function _claimableDepositRequest(address _kernel, address _asset, address _controller) internal returns (uint256 claimableAssets) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.claimableDepositRequest, (_asset, _controller)));
        return abi.decode(returnData, (uint256));
    }

    /**
     * @notice Gets the pending redeem request amount
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return pendingShares The amount of shares pending redemption in the request
     */
    function _pendingRedeemRequest(address _kernel, address _asset, address _controller) internal returns (uint256 pendingShares) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.pendingRedeemRequest, (_asset, _controller)));
        return abi.decode(returnData, (uint256));
    }

    /**
     * @notice Gets the claimable redeem request amount
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return claimableShares The amount of shares redeemable in the request
     */
    function _claimableRedeemRequest(address _kernel, address _asset, address _controller) internal returns (uint256 claimableShares) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.claimableRedeemRequest, (_asset, _controller)));
        return abi.decode(returnData, (uint256));
    }

    /**
     * @notice Executes a deposit to the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to deposit
     * @param _controller The address of the controller
     * @param _amount The amount of assets to deposit
     */
    function _deposit(address _kernel, address _asset, address _controller, uint256 _amount) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.deposit, (_asset, _controller, _amount)));
    }

    /**
     * @notice Requests a withdrawal from the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to withdraw
     * @param _controller The address of the controller
     * @param _amount The amount of assets to withdraw
     */
    function _requestWithdraw(address _kernel, address _asset, address _controller, uint256 _amount) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.requestWithdraw, (_asset, _controller, _amount)));
    }

    /**
     * @notice Executes a withdrawal from the kernel
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset to withdraw
     * @param _controller The address of the controller
     * @param _amount The amount to withdraw
     * @param _receiver The address to receive the withdrawn assets
     */
    function _withdraw(address _kernel, address _asset, address _controller, uint256 _amount, address _receiver) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.withdraw, (_asset, _controller, _amount, _receiver)));
    }

    /**
     * @notice Cancels a deposit request
     * @param _kernel The address of the kernel contract
     * @param _controller The address of the controller
     */
    function _cancelDepositRequest(address _kernel, address _controller) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.cancelDepositRequest, (_controller)));
    }

    /**
     * @notice Checks if a deposit cancellation request is pending
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return isPending True if cancellation request is pending
     */
    function _pendingCancelDepositRequest(address _kernel, address _asset, address _controller) internal returns (bool isPending) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.pendingCancelDepositRequest, (_asset, _controller)));
        return abi.decode(returnData, (bool));
    }

    /**
     * @notice Gets the claimable amount from a deposit cancellation request
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return assets The amount of assets claimable from the deposit cancellation
     */
    function _claimableCancelDepositRequest(address _kernel, address _asset, address _controller) internal returns (uint256 assets) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.claimableCancelDepositRequest, (_asset, _controller)));
        return abi.decode(returnData, (uint256));
    }

    /**
     * @notice Cancels a redeem request
     * @param _kernel The address of the kernel contract
     * @param _controller The address of the controller
     */
    function _cancelRedeemRequest(address _kernel, address _controller) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.cancelRedeemRequest, (_controller)));
    }

    /**
     * @notice Checks if a redeem cancellation request is pending
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return isPending True if cancellation request is pending
     */
    function _pendingCancelRedeemRequest(address _kernel, address _asset, address _controller) internal returns (bool isPending) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.pendingCancelRedeemRequest, (_asset, _controller)));
        return abi.decode(returnData, (bool));
    }

    /**
     * @notice Gets the claimable amount from a redeem cancellation request
     * @param _kernel The address of the kernel contract
     * @param _asset The address of the asset
     * @param _controller The address of the controller
     * @return shares The amount of shares claimable from the redeem cancellation
     */
    function _claimableCancelRedeemRequest(address _kernel, address _asset, address _controller) internal returns (uint256 shares) {
        bytes memory returnData = _delegateCallKernel(_kernel, abi.encodeCall(IRoycoKernel.claimableCancelRedeemRequest, (_asset, _controller)));
        return abi.decode(returnData, (uint256));
    }

    /**
     * @notice Checks if the kernel supports deposit cancellation
     * @param _kernel The address of the kernel contract
     * @return True if deposit cancellation is supported
     */
    function _SUPPORTS_DEPOSIT_CANCELLATION(address _kernel) internal pure returns (bool) {
        return IRoycoKernel(_kernel).SUPPORTS_DEPOSIT_CANCELLATION();
    }

    /**
     * @notice Checks if the kernel supports redemption cancellation
     * @param _kernel The address of the kernel contract
     * @return True if redemption cancellation is supported
     */
    function _SUPPORTS_REDEMPTION_CANCELLATION(address _kernel) internal pure returns (bool) {
        return IRoycoKernel(_kernel).SUPPORTS_REDEMPTION_CANCELLATION();
    }

    /**
     * @notice Executes a delegate call to the kernel with error handling
     * @param _kernel The address of the kernel contract
     * @param _callData The encoded function call data
     * @return The return data from the delegate call
     */
    function _delegateCallKernel(address _kernel, bytes memory _callData) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = _kernel.delegatecall(_callData);
        require(success, KERNEL_DELEGATECALL_FAILED(_callData, returnData));
        return returnData;
    }
}
