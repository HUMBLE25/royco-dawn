// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncJTWithdrawalKernel
 * @notice Interface for Royco kernels that employ an asynchronous withdrawal flow for the junior tranche
 * @dev We mandate that kernels implement the cancellation functions because of the market's utilization changing between request and claim
 *      if the underlying investment opportunity supports it
 */
interface IAsyncJTWithdrawalKernel {
    /**
     * @notice Requests a redemption for a specified amount of shares from the underlying investment opportunity
     * @param _caller The address of the user requesting the withdrawal for the junior tranche
     * @param _assets The amount of assets being requested to be redeemed
     * @param _controller The controller that is allowed to operate the lifecycle of the request.
     * @return requestId The request ID of this withdrawal request
     */
    function jtRequestWithdrawal(address _caller, uint256 _assets, address _controller) external returns (uint256 requestId);

    /**
     * @notice Returns the amount of assets pending redemption for a specific controller
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The controller to query pending redemptions for
     * @return pendingAssets The amount of assets pending redemption for the controller
     */
    function jtPendingWithdrawalRequest(uint256 _requestId, address _controller) external view returns (uint256 pendingAssets);

    /**
     * @notice Returns the amount of shares claimable from completed redemption requests for a specific controller
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The controller to query claimable redemptions for
     * @return claimableShares The amount of shares claimable from completed redemption requests
     */
    function jtClaimableWithdrawalRequest(uint256 _requestId, address _controller) external view returns (uint256 claimableShares);

    /**
     * @notice Cancels a pending redeem request for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have a pending redeem request with this requestId and/or controller
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller that is allowed to operate the cancellation
     */
    function jtCancelWithdrawalRequest(uint256 _requestId, address _controller) external;

    /**
     * @notice Returns whether there is a pending redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending redeem cancellation
     */
    function jtPendingCancelWithdrawalRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of shares claimable from a redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for claimable cancellation shares
     * @return shares The amount of shares claimable from redeem cancellation
     */
    function jtClaimableCancelWithdrawalRequest(uint256 _requestId, address _controller) external view returns (uint256 shares);
}

