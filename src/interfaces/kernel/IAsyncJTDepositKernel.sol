// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAsyncJTDepositKernel
 * @notice Interface for Royco kernels that employ an asynchronous deposit flow for the junior tranche
 * @dev We mandate that kernels implement the cancellation functions because of the market's utilization changing between request and claim
 *      if the underlying investment opportunity supports it
 */
interface IAsyncJTDepositKernel {
    /**
     * @notice Requests a deposit of a specified amount of an asset into the underlying investment opportunity
     * @param _caller The address of the user requesting the deposit for the junior tranche
     * @param _assets The amount of the asset to deposit into the underlying investment opportunity
     * @param _controller The controller that is allowed to operate the lifecycle of this deposit request
     * @return requestId The request ID of this deposit request
     */
    function jtRequestDeposit(address _caller, uint256 _assets, address _controller) external returns (uint256 requestId);

    /**
     * @notice Returns the amount of assets pending deposit for a specified controller
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller corresponding to this request
     * @return pendingAssets The amount of assets pending deposit for the controller
     */
    function jtPendingDepositRequest(uint256 _requestId, address _controller) external returns (uint256 pendingAssets);

    /**
     * @notice Returns the amount of assets claimable from a processed deposit request for a specified controller
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller corresponding to this request
     * @return claimableAssets The amount of assets claimable from processed deposit request
     */
    function jtClaimableDepositRequest(uint256 _requestId, address _controller) external returns (uint256 claimableAssets);

    /**
     * @notice Cancels a pending deposit request for the specified controller
     * @dev The tranche calling this function must have a pending deposit request with this requestId and/or controller
     * @param _caller The address of the user requesting the cancelation of a deposit request for the junior tranche
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller that is allowed to operate the lifecycle of this cancellation request
     */
    function jtCancelDepositRequest(address _caller, uint256 _requestId, address _controller) external;

    /**
     * @notice Returns whether there is a pending deposit cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports deposit cancellation for the junior tranche
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending deposit cancellation
     */
    function jtPendingCancelDepositRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of assets claimable from a deposit cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports deposit cancellation for the junior tranche
     * @param _requestId The request ID of this deposit request
     * @param _controller The controller to query for claimable cancellation assets
     * @return assets The amount of assets claimable from deposit cancellation
     */
    function jtClaimableCancelDepositRequest(uint256 _requestId, address _controller) external view returns (uint256 assets);
}
