// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncJTWithdrawalKernel
 * @notice Interface for Royco kernels that employ an asynchronous withdrawal flow for the junior tranche
 */
interface IAsyncJTWithdrawalKernel {
    /**
     * @notice Requests a redemption for a specified amount of shares from the underlying investment opportunity
     * @param _caller The address of the user requesting the withdrawal for the junior tranche
     * @param _shares The amount of shares of the junior tranche being requested to be redeemed
     * @param _controller The controller that is allowed to operate the lifecycle of the request.
     * @return requestId The request ID of this withdrawal request
     */
    function jtRequestRedeem(address _caller, uint256 _shares, address _controller) external returns (uint256 requestId);

    /**
     * @notice Returns the amount of assets pending redemption for a specific controller
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The controller to query pending redemptions for
     * @return pendingShares The amount of shares pending redemption for the controller
     */
    function jtPendingRedeemRequest(uint256 _requestId, address _controller) external view returns (uint256 pendingShares);

    /**
     * @notice Returns the amount of shares claimable from completed redemption requests for a specific controller
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The controller to query claimable redemptions for
     * @return claimableShares The amount of shares claimable from completed redemption requests
     */
    function jtClaimableRedeemRequest(uint256 _requestId, address _controller) external view returns (uint256 claimableShares);

    /**
     * @notice Cancels a pending redeem request for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @dev The tranche calling this function must have a pending redeem request with this requestId and/or controller
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller that is allowed to operate the cancellation
     */
    function jtCancelRedeemRequest(uint256 _requestId, address _controller) external;

    /**
     * @notice Claims a cancelled redeem request for a specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _receiver The receiver of the cancelled redeem assets
     * @param _controller The controller corresponding to this request
     * @return shares The amount of shares claimed from the cancelled redeem request
     */
    function jtClaimCancelRedeemRequest(uint256 _requestId, address _receiver, address _controller) external returns (uint256 shares);

    /**
     * @notice Returns whether there is a pending redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending redeem cancellation
     */
    function jtPendingCancelRedeemRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of shares claimable from a redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for claimable cancellation assets
     * @return shares The amount of shares claimable from redeem cancellation
     */
    function jtClaimableCancelRedeemRequest(uint256 _requestId, address _controller) external view returns (uint256 shares);
}
