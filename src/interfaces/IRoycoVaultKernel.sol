// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IRoycoVaultKernel
 * @notice Interface for kernel contracts that handle asset management operations to/from an underlying protocol
 * @dev Provides the logic for RoycoNetVaults to interact with external protocols (e.g., Aave, Compound)
 * @dev Kernels have no conception of shares, so its interactions and interface relate to assets exclusively
 * @dev Kernels support both synchronous and asynchronous operations via ActionType enum
 * @dev Asynchronous operations use a request/claim pattern for deposits and withdrawals
 * @dev Kernels may optionally support cancellation of pending requests (ERC-7887)
 */
interface IRoycoVaultKernel {
    /**
     * @title ActionType
     * @dev Defines the execution semantics for the deposit or withdrawal flow of a vault
     * @custom:type SYNC Refers to the flow being synchronous (the vault uses ERC4626 for this flow)
     * @custom:type ASYNC Refers to the flow being asynchronous (the vault uses ERC7540 for this flow)
     */
    enum ActionType {
        SYNC,
        ASYNC
    }

    // =============================
    // Kernel Configuration
    // =============================

    /**
     * @notice Returns the deposit type of the kernel
     * @return The deposit type of the kernel
     */
    function DEPOSIT_TYPE() external pure returns (ActionType);

    /**
     * @notice Returns the withdraw type of the kernel
     * @return The withdraw type of the kernel
     */
    function WITHDRAW_TYPE() external pure returns (ActionType);

    /**
     * @notice Returns whether the kernel supports deposit cancellation
     * @return Whether the kernel supports deposit cancellation
     */
    function SUPPORTS_DEPOSIT_CANCELLATION() external pure returns (bool);

    /**
     * @notice Returns whether the kernel supports redeem cancellation
     * @return Whether the kernel supports redeem cancellation
     */
    function SUPPORTS_REDEMPTION_CANCELLATION() external pure returns (bool);

    // =============================
    // Core Asset Management
    // =============================

    /**
     * @notice Returns the total amount of a specific asset managed by the caller in the underlying protocol
     * @dev Must be called via a call or staticcall (reliant on msg.sender)
     * @param _asset The address of the asset to query the owner's balance in the underlying protocol for
     * @return The total amount of the specified asset managed by the caller
     */
    function totalAssets(address _asset) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of a specific asset that can be deposited into the underlying protocol
     * @param _asset The address of the asset to deposit
     * @return The maximum amount of the asset that can be globally deposited into the underlying protocol
     */
    function maxDeposit(address _asset) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of a specific asset that can be withdrawn from the underlying protocol
     * @param _asset The address of the asset to withdraw
     * @return The maximum amount of assets that can be globally withdrawn from the underlying protocol
     */
    function maxWithdraw(address _asset) external view returns (uint256);

    // =============================
    // Asynchronous Deposit Operations
    // =============================

    /**
     * @notice Requests a deposit of a specified amount of an asset into the underlying protocol
     * @dev This function is only callable if and only if the deposit type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must hold the specified amount of assets to deposit
     * @param _asset The address of the asset to deposit into the underlying protocol
     * @param _controller The controller that is allowed to operate the request. All accounting is done against the controller.
     * @param _amount The amount of the asset to deposit into the underlying protocol
     * @param _amount The request ID for the deposit request
     */
    function requestDeposit(address _asset, address _controller, uint256 _amount) external;

    /**
     * @notice Returns the amount of assets pending deposit for a specific controller
     * @dev This function is only relevant if the deposit type of the kernel is ASYNC
     * @param _asset The address of the asset to query pending deposits for
     * @param _controller The controller to query pending deposits for
     * @return pendingAssets The amount of assets pending deposit for the controller
     */
    function pendingDepositRequest(address _asset, address _controller) external view returns (uint256 pendingAssets);

    /**
     * @notice Returns the amount of assets claimable from completed deposit requests for a specific controller
     * @dev This function is only relevant if the deposit type of the kernel is ASYNC
     * @param _asset The address of the asset to query claimable deposits for
     * @param _controller The controller to query claimable deposits for
     * @return claimableAssets The amount of assets claimable from completed deposit requests
     */
    function claimableDepositRequest(address _asset, address _controller) external view returns (uint256 claimableAssets);

    /**
     * @notice Deposits a specified amount of an asset into the underlying protocol
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must hold the specified amount of assets to deposit
     * @param _asset The address of the asset to deposit into the underlying protocol
     * @param _controller The controller that is allowed to operate the deposit. All accounting is done against the controller.
     * @param _amount The amount of the asset to deposit into the underlying protocol
     */
    function deposit(address _asset, address _controller, uint256 _amount) external;

    // =============================
    // Asynchronous Withdrawal Operations
    // =============================

    /**
     * @notice Requests a withdrawal of a specified amount of an asset from the underlying protocol
     * @dev This function is only callable if and only if the withdraw type of the kernel is ASYNC
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have a balance greater than or equal to the specified amount of assets in the underlying protocol
     * @param _asset The address of the asset to withdraw from the underlying protocol
     * @param _controller The controller that is allowed to operate the request. All accounting is done against the controller.
     * @param _amount The amount of the asset to withdraw from the underlying protocol
     */
    function requestWithdraw(address _asset, address _controller, uint256 _amount) external;

    /**
     * @notice Returns the amount of shares pending redemption for a specific controller
     * @dev This function is only relevant if the withdraw type of the kernel is ASYNC
     * @param _asset The address of the asset to query pending redemptions for
     * @param _controller The controller to query pending redemptions for
     * @return pendingShares The amount of shares pending redemption for the controller
     */
    function pendingRedeemRequest(address _asset, address _controller) external view returns (uint256 pendingShares);

    /**
     * @notice Returns the amount of shares claimable from completed redemption requests for a specific controller
     * @dev This function is only relevant if the withdraw type of the kernel is ASYNC
     * @param _asset The address of the asset to query claimable redemptions for
     * @param _controller The controller to query claimable redemptions for
     * @return claimableShares The amount of shares claimable from completed redemption requests
     */
    function claimableRedeemRequest(address _asset, address _controller) external view returns (uint256 claimableShares);

    /**
     * @notice Withdraws a specified amount of an asset from the underlying protocol
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have a balance greater than or equal to the specified amount of assets in the underlying protocol
     * @param _asset The address of the asset to withdraw from the underlying protocol
     * @param _controller The controller that is allowed to operate the withdrawal. All accounting is done against the controller.
     * @param _amount The amount of the asset to withdraw from the underlying protocol
     * @param _recipient The recipient of the withdrawn assets
     */
    function withdraw(address _asset, address _controller, uint256 _amount, address _recipient) external;

    // =============================
    // Cancellation Operations
    // =============================

    /**
     * @notice Cancels a pending deposit request for the specified controller
     * @dev This function is only callable if the kernel supports deposit cancellation
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have pending deposit requests for the controller
     * @param _controller The controller that is allowed to operate the cancellation
     */
    function cancelDepositRequest(address _controller) external;

    /**
     * @notice Returns whether there is a pending deposit cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports deposit cancellation
     * @param _asset The address of the asset to query for pending cancellation
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending deposit cancellation
     */
    function pendingCancelDepositRequest(address _asset, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of assets claimable from a deposit cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports deposit cancellation
     * @param _asset The address of the asset to query for claimable cancellation assets
     * @param _controller The controller to query for claimable cancellation assets
     * @return assets The amount of assets claimable from deposit cancellation
     */
    function claimableCancelDepositRequest(address _asset, address _controller) external view returns (uint256 assets);

    /**
     * @notice Cancels a pending redeem request for the specified controller
     * @dev This function is only callable if the kernel supports redeem cancellation
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have pending redeem requests for the controller
     * @param _controller The controller that is allowed to operate the cancellation
     */
    function cancelRedeemRequest(address _controller) external;

    /**
     * @notice Returns whether there is a pending redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _asset The address of the asset to query for pending cancellation
     * @param _controller The controller to query for pending cancellation
     * @return isPending True if there is a pending redeem cancellation
     */
    function pendingCancelRedeemRequest(address _asset, address _controller) external view returns (bool isPending);

    /**
     * @notice Returns the amount of shares claimable from a redeem cancellation for the specified controller
     * @dev This function is only relevant if the kernel supports redeem cancellation
     * @param _asset The address of the asset to query for claimable cancellation shares
     * @param _controller The controller to query for claimable cancellation shares
     * @return shares The amount of shares claimable from redeem cancellation
     */
    function claimableCancelRedeemRequest(address _asset, address _controller) external view returns (uint256 shares);
}
