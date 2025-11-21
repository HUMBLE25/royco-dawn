// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncDepositKernel
 * @notice Interface for Royco kernels that employ an asynchronous deposit flow
 * @notice We mandate that kernels implement the cancellation functions because of coverage changing between request and claim
 */
interface IAsyncDepositKernel {
    /**
     * @notice Requests a deposit of a specified amount of an asset into the underlying investment opportunity
     * @dev This function is only callable if and only if the deposit type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The tranche delegatecalling this function must hold the specified amount of assets to deposit
     * @param _assets The amount of the asset to deposit into the underlying investment opportunity
     * @param _controller The controller that is allowed to operate the lifecycle of the request.
     * @return requestId The request ID of this deposit request
     */
    function requestDeposit(uint256 _assets, address _controller) external returns (uint256 requestId);

    /**
     * @notice Returns the amount of assets pending deposit for a specific controller
     * @dev This function is only callable if and only if the deposit type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller corresponding to this request
     * @return pendingAssets The amount of assets pending deposit for the controller
     */
    function pendingDepositRequest(uint256 _requestId, address _controller) external returns (uint256 pendingAssets);

    /**
     * @notice Returns the amount of assets claimable from completed deposit requests for a specific controller
     * @dev This function is only callable if and only if the deposit type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller corresponding to this request
     * @return claimableAssets The amount of assets claimable from completed deposit requests
     */
    function claimableDepositRequest(uint256 _requestId, address _controller) external returns (uint256 claimableAssets);

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
}
