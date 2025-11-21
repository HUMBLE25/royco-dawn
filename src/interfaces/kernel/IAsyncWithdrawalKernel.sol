// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncWithdrawalKernel
 * @notice Interface for Royco kernels that employ an asynchronous withdrawal flow
 * @notice Kernels must implement the cancellation functions because of coverage changes between request and claim
 */
interface IAsyncWithdrawalKernel {
    /**
     * @notice Requests a redemption for a specified amount of shares from the underlying investment opportunity
     * @dev This function is only callable if and only if the withdrawal type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @param _expectedAssets The expected amount of assets to receive for the shares redeemed based on currently reported NAV (not binding)
     * @param _shares The amount of shares being requested to be redeemed
     * @param _controller The controller that is allowed to operate the lifecycle of the request.
     * @return requestId The request ID of this withdrawal request
     */
    function requestRedeem(uint256 _expectedAssets, uint256 _shares, address _controller) external returns (uint256 requestId);

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

    /**
     * @notice Cancels a pending redeem request for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have a pending redeem request with this requestId and/or controller
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller that is allowed to operate the cancellation
     */
    function cancelRedeemRequest(uint256 _requestId, address _controller) external;

    /**
     * @notice Returns whether there is a pending redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending redeem cancellation
     */
    function pendingCancelRedeemRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of shares claimable from a redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for claimable cancellation shares
     * @return shares The amount of shares claimable from redeem cancellation
     */
    function claimableCancelRedeemRequest(uint256 _requestId, address _controller) external view returns (uint256 shares);
}
