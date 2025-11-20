// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncWithdrawalKernel
 * @notice Interface for Royco kernels that employ an asynchronous withdrawal flow
 */
interface IAsyncWithdrawalKernel {
    /**
     * @notice Requests a redemption for a specified amount of shares from the underlying investment opportunity
     * @dev This function is only callable if and only if the withdrawal type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @param _asset The address of the asset to withdraw from the underlying investment opportunity
     * @param _expectedAssets The expected amount of assets to receive for the shares redeemed based on currently reported NAV (not binding)
     * @param _shares The amount of shares being requested to be redeemed
     * @param _controller The controller that is allowed to operate the lifecycle of the request.
     * @return requestId The request ID of this withdrawal request
     */
    function requestRedeem(address _asset, uint256 _expectedAssets, uint256 _shares, address _controller) external returns (uint256 requestId);

    /**
     * @notice Returns the amount of shares pending redemption for a specific controller
     * @dev This function is only callable if and only if the withdrawal type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The controller to query pending redemptions for
     * @return pendingShares The amount of shares pending redemption for the controller
     */
    function pendingRedeemRequest(uint256 _requestId, address _controller) external returns (uint256 pendingShares);

    /**
     * @notice Returns the amount of shares claimable from completed redemption requests for a specific controller
     * @dev This function is only callable if and only if the withdrawal type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The controller to query claimable redemptions for
     * @return claimableShares The amount of shares claimable from completed redemption requests
     */
    function claimableRedeemRequest(uint256 _requestId, address _controller) external returns (uint256 claimableShares);
}
