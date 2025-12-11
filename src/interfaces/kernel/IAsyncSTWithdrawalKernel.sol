// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncSTWithdrawalKernel
 * @notice Interface for Royco kernels that employ an asynchronous withdrawal flow for the senior tranche
 * @dev We mandate that kernels implement the cancellation functions because of the market's utilization changing between request and claim
 *      if the underlying investment opportunity supports it
 */
interface IAsyncSTWithdrawalKernel {
    /**
     * @notice Requests a redemption for a specified amount of shares from the underlying investment opportunity
     * @param _caller The address of the user requesting the withdrawal for the senior tranche
     * @param _shares The amount of shares of the senior tranche being requested to be redeemed
     * @param _totalShares The total number of shares in the senior tranche at the time of the request
     * @param _controller The controller that is allowed to operate the lifecycle of the request.
     * @return requestId The request ID of this withdrawal request
     */
    function stRequestWithdrawal(address _caller, uint256 _shares, uint256 _totalShares, address _controller) external returns (uint256 requestId);

    /**
     * @notice Returns the amount of assets pending redemption for a specific controller
     * @param _requestId The request ID of this withdrawal request
     * @param _totalShares The total number of shares in the senior tranche at the time of the request
     * @param _controller The controller to query pending redemptions for
     * @return pendingAssets The amount of assets pending redemption for the controller
     */
    function stPendingWithdrawalRequest(uint256 _requestId, uint256 _totalShares, address _controller) external view returns (uint256 pendingAssets);

    /**
     * @notice Returns the amount of shares claimable from completed redemption requests for a specific controller
     * @param _requestId The request ID of this withdrawal request
     * @param _controller The controller to query claimable redemptions for
     * @return claimableShares The amount of shares claimable from completed redemption requests
     */
    function stClaimableWithdrawalRequest(uint256 _requestId, uint256 _totalShares, address _controller) external view returns (uint256 claimableShares);

    /**
     * @notice Cancels a pending redeem request for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have a pending redeem request with this requestId and/or controller
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller that is allowed to operate the cancellation
     */
    function stCancelWithdrawalRequest(uint256 _requestId, address _controller) external;

    /**
     * @notice Returns whether there is a pending redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending redeem cancellation
     */
    function stPendingCancelWithdrawalRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of shares claimable from a redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for claimable cancellation shares
     * @return shares The amount of shares claimable from redeem cancellation
     */
    function stClaimableCancelWithdrawalRequest(uint256 _requestId, address _controller) external view returns (uint256 shares);
}
