// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TRANCHE_UNIT } from "../../libraries/Units.sol";

/// @title IRoycoAsyncCancellableVault: based on ERC-7887: Cancellation for ERC-7540 Tokenized Vaults
/// @notice Interface extending ERC-7540 asynchronous vaults with cancellation flows
interface IRoycoAsyncCancellableVault {
    // =============================
    // Events
    // =============================

    /// @notice Emitted when a controller requests cancellation of a deposit Request
    /// @param controller The controller of the Request (may equal msg.sender or its approved operator)
    /// @param requestId The identifier of the deposit Request being canceled
    /// @param sender The caller of the cancelDepositRequest
    event CancelDepositRequest(address indexed controller, uint256 indexed requestId, address sender);

    /// @notice Emitted when a controller claims a deposit cancellation
    /// @param controller The controller of the canceled Request
    /// @param receiver The recipient of the returned assets
    /// @param requestId The identifier of the canceled Request
    /// @param sender The caller of the claimCancelDepositRequest
    /// @param assets The amount of assets claimed
    event CancelDepositClaim(address indexed controller, address indexed receiver, uint256 indexed requestId, address sender, TRANCHE_UNIT assets);

    /// @notice Emitted when a controller requests cancellation of a redeem Request
    /// @param controller The controller of the Request (may equal msg.sender or its approved operator)
    /// @param requestId The identifier of the redeem Request being canceled
    /// @param sender The caller of the cancelRedeemRequest
    event CancelRedeemRequest(address indexed controller, uint256 indexed requestId, address sender);

    /// @notice Emitted when a controller claims a redeem cancellation
    /// @param controller The controller of the canceled Request
    /// @param receiver The recipient of the returned shares
    /// @param requestId The identifier of the canceled Request
    /// @param sender The caller of the claimCancelRedeemRequest
    /// @param shares The amount of shares claimed
    event CancelRedeemClaim(address indexed controller, address indexed receiver, uint256 indexed requestId, address sender, uint256 shares);

    // =============================
    // Deposit Cancellation
    // =============================

    /// @notice Submit an asynchronous deposit cancellation Request
    /// @dev MUST emit {CancelDepositRequest}
    /// @param _requestId The identifier of the original deposit Request
    /// @param _controller The controller of the Request (must equal msg.sender unless operator-approved)
    function cancelDepositRequest(uint256 _requestId, address _controller) external;

    /// @notice Returns whether a deposit cancellation Request is pending for the given controller
    /// @dev MUST NOT vary by caller or revert except for unreasonable input overflow
    /// @param _requestId The identifier of the original deposit Request
    /// @param _controller The controller address
    /// @return isPending True if the cancellation is pending
    function pendingCancelDepositRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /// @notice Returns the amount of assets claimable for a deposit cancellation Request for the controller
    /// @dev MUST NOT vary by caller or revert except for unreasonable input overflow
    /// @param _requestId The identifier of the original deposit Request
    /// @param _controller The controller address
    /// @return assets The amount of assets claimable
    function claimableCancelDepositRequest(uint256 _requestId, address _controller) external view returns (TRANCHE_UNIT assets);

    /// @notice Claim a deposit cancellation Request, transferring assets to the receiver
    /// @dev MUST emit {CancelDepositClaim}
    /// @param _requestId The identifier of the canceled deposit Request
    /// @param _receiver The recipient of assets
    /// @param _controller The controller of the Request (must equal msg.sender unless operator-approved)
    function claimCancelDepositRequest(uint256 _requestId, address _receiver, address _controller) external;

    // =============================
    // Redeem Cancellation
    // =============================

    /// @notice Submit an asynchronous redeem cancellation Request
    /// @dev MUST emit {CancelRedeemRequest}
    /// @param _requestId The identifier of the original redeem Request
    /// @param _controller The controller of the Request (must equal msg.sender unless operator-approved)
    function cancelRedeemRequest(uint256 _requestId, address _controller) external;

    /// @notice Returns whether a redeem cancellation Request is pending for the given controller
    /// @dev MUST NOT vary by caller or revert except for unreasonable input overflow
    /// @param _requestId The identifier of the original redeem Request
    /// @param _controller The controller address
    /// @return isPending True if the cancellation is pending
    function pendingCancelRedeemRequest(uint256 _requestId, address _controller) external view returns (bool isPending);

    /// @notice Returns the amount of shares claimable for a redeem cancellation Request for the controller
    /// @dev MUST NOT vary by caller or revert except for unreasonable input overflow
    /// @param _requestId The identifier of the original redeem Request
    /// @param _controller The controller address
    /// @return shares The amount of shares claimable
    function claimableCancelRedeemRequest(uint256 _requestId, address _controller) external view returns (uint256 shares);

    /// @notice Claim a redeem cancellation Request, transferring shares to the receiver
    /// @dev MUST emit {CancelRedeemClaim}
    /// @param _requestId The identifier of the canceled redeem Request
    /// @param _receiver The recipient of shares
    /// @param _controller The controller address
    function claimCancelRedeemRequest(uint256 _requestId, address _receiver, address _controller) external;
}
