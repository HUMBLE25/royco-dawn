// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncDepositKernel
 * @notice Interface for Royco kernels that employ an asynchronous deposit flow
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
}
