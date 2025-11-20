// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncWithdrawalKernel
 * @notice Interface for Royco kernels that employ an asynchronous withdrawal flow
 */
interface ICancellableKernel {
    /**
     * @notice Cancels a pending deposit request for the specified controller
     * @dev This function is only callable if the kernel supports deposit cancellation
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have a pending deposit request with this requestId and/or controller
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller that is allowed to operate the cancellation
     */
    function cancelDepositRequest(uint256 _requestId, address _controller) external;

    /**
     * @notice Returns whether there is a pending deposit cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports deposit cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending deposit cancellation
     */
    function pendingCancelDepositRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of assets claimable from a deposit cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports deposit cancellation
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for claimable cancellation assets
     * @return assets The amount of assets claimable from deposit cancellation
     */
    function claimableCancelDepositRequest(uint256 _requestId, address _controller) external view returns (uint256 assets);

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
