// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title ExecutionModel
 * @dev Defines the execution semantics for the deposit or withdrawal flow of a vault
 * @custom:type SYNC Refers to the flow being synchronous (the vault uses ERC4626 for this flow)
 * @custom:type ASYNC Refers to the flow being asynchronous (the vault uses ERC7540 for this flow)
 */
enum ExecutionModel {
    SYNC,
    ASYNC
}

/**
 * @title IBaseKernel
 * @notice Base interface for Royco kernel contracts that handle asset management operations to/from an underlying investment opportunity
 * @dev Provides the logic for Royco Tranches to interact with external investment opportunities (e.g., Aave, Ethena, RWAs, etc.)
 * @dev Kernels support both synchronous and asynchronous flows for deposits and withdrawals via ExecutionModel enum
 * @dev Asynchronous operations use a request/claim pattern for deposits and withdrawals (ERC7540).
 *       Must implement IAsyncDepostKernel and/or IAsyncWithdrawalKernel if using asynchronous flows.
 * @dev Kernels may optionally support cancellation of pending requests (ERC7887). Must implement ICancellableKernel if supported.
 */
interface IBaseKernel {
    // =============================
    // Kernel Configuration
    // =============================

    /**
     * @notice Returns the deposit type of the kernel
     * @return The deposit type of the kernel
     */
    function DEPOSIT_EXECUTION_MODEL() external pure returns (ExecutionModel);

    /**
     * @notice Returns the withdraw type of the kernel
     * @return The withdraw type of the kernel
     */
    function WITHDRAW_EXECUTION_MODEL() external pure returns (ExecutionModel);

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
    // Core Asset Management Getters
    // =============================

    /**
     * @notice Returns the net asset value managed by the caller in the underlying investment opportunity
     * @dev Must be called via a call or staticcall (reliant on msg.sender)
     * @param _asset The address of the asset to query the owner's balance in the underlying investment opportunity for
     * @return The total amount of the specified asset managed by the caller
     */
    function getNAV(address _asset) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of a specific asset that can be deposited into the underlying investment opportunity
     * @dev Must be called via a call or staticcall (reliant on msg.sender)
     * @param _reciever The address that will be asserting ownership over the deposited assets
     * @param _asset The address of the asset to deposit
     * @return The maximum amount of the asset that can be deposited into the underlying investment opportunity
     */
    function maxDeposit(address _reciever, address _asset) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of a specific asset that can be withdrawn from the underlying investment opportunity
     * @dev Must be called via a call or staticcall (reliant on msg.sender)
     * @param _owner The address that holds ownership over the deposited assets
     * @param _asset The address of the asset to withdraw
     * @return The maximum amount of assets that can be withdrawn from the underlying investment opportunity
     */
    function maxWithdraw(address _owner, address _asset) external view returns (uint256);

    // =============================
    // Deposit and Withdrawal Operations
    // =============================

    /**
     * @notice Deposits a specified amount of an asset into the underlying investment opportunity
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must hold the specified amount of assets to deposit
     * @param _asset The address of the asset to deposit into the underlying investment opportunity
     * @param _assets The amount of the asset to deposit into the underlying investment opportunity
     * @param _controller The controller that is allowed to operate the lifecycle of the request.
     */
    function deposit(address _asset, uint256 _assets, address _controller) external;

    /**
     * @notice Withdraws a specified amount of an asset from the underlying investment opportunity
     * @dev Must be called via a delegatecall (reliant on address(this))
     * @dev The contract delegatecalling this function must have a balance greater than or equal to the specified amount of assets in the underlying investment opportunity
     * @param _asset The address of the asset to withdraw from the underlying investment opportunity
     * @param _assets The amount of the asset to withdraw from the underlying investment opportunity
     * @param _controller The controller that is allowed to operate the withdrawal.
     * @param _receiver The recipient of the withdrawn assets
     */
    function withdraw(address _asset, uint256 _assets, address _controller, address _receiver) external;
}
