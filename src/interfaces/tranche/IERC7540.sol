// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IERC7540
 * @notice ERC-7540: Asynchronous ERC-4626 Tokenized Vaults
 * @dev Specification: https://eips.ethereum.org/EIPS/eip-7540
 *
 * Extends ERC-4626 with asynchronous Request flows for deposits and/or redemptions.
 * Implementations MAY choose to support either or both async flows; unsupported flows
 * MUST follow ERC-4626 synchronous behavior. Implementations MUST support ERC-165.
 *
 * Key definitions:
 * - Request: requestDeposit/requestRedeem to enter/exit the vault asynchronously
 * - Pending: Request submitted, not yet claimable
 * - Claimable: Request processed; controller can claim using ERC-4626 claim functions
 * - Claimed: Request finalized via ERC-4626 deposit/mint or redeem/withdraw
 * - controller: owner of the Request; can manage and claim it (or via operator)
 * - operator: account approved to act on behalf of a controller
 */
interface IERC7540 {
    /// @notice Operator approval updated for a controller.
    /// @dev MUST be logged when operator status is set; MAY be logged when unchanged.
    /// @param owner The controller setting an operator.
    /// @param operator The operator being approved/revoked.
    /// @param approved New approval status.
    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    /// @notice Assets locked to request an asynchronous deposit.
    /// @dev MUST be emitted by requestDeposit.
    /// @param controller The controller of the Request.
    /// @param owner The owner whose assets were locked.
    /// @param requestId The identifier for the Request (see Request Ids semantics).
    /// @param sender The caller of requestDeposit (may differ from owner).
    /// @param assets The amount of assets requested.
    event DepositRequest(address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets);

    /// @notice Shares locked (or assumed control of) to request an asynchronous redemption.
    /// @dev MUST be emitted by requestRedeem.
    /// @param controller The controller of the Request (may differ from owner).
    /// @param owner The owner whose shares were locked or assumed.
    /// @param requestId The identifier for the Request (see Request Ids semantics).
    /// @param sender The caller of requestRedeem (may differ from owner).
    /// @param shares The amount of shares requested to redeem.
    event RedeemRequest(address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares);

    /// @notice Transfer assets from owner and submit an async deposit Request.
    /// @dev MUST emit DepositRequest. MUST support ERC20 approve/transferFrom on the asset.
    /// @dev MUST revert if all assets cannot be requested (limits/slippage/approval/etc).
    /// @param assets Amount of assets to request.
    /// @param controller Controller of the Request (msg.sender unless operator-approved).
    /// @param owner Source of the assets; MUST be msg.sender unless operator-approved.
    /// @return requestId Discriminator paired with controller (see Request Ids semantics).
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    /// @notice Amount of requested assets in Pending state for controller/requestId.
    /// @dev MUST NOT include amounts in Claimable; MUST NOT vary by caller.
    /// @param requestId Request identifier.
    /// @param controller Controller address.
    /// @return pendingAssets Amount in Pending.
    function pendingDepositRequest(uint256 requestId, address controller) external returns (uint256 pendingAssets);

    /// @notice Amount of requested assets in Claimable state for controller/requestId.
    /// @dev MUST NOT include amounts in Pending; MUST NOT vary by caller.
    /// @param requestId Request identifier.
    /// @param controller Controller address.
    /// @return claimableAssets Amount in Claimable.
    function claimableDepositRequest(uint256 requestId, address controller) external returns (uint256 claimableAssets);

    /// @notice Claim an async deposit by calling ERC-4626 deposit.
    /// @dev Overload per ERC-7540. MUST revert unless msg.sender == controller or operator.
    /// @param assets Assets to claim.
    /// @param receiver Recipient of shares.
    /// @param controller Controller discriminating the claim when sender is operator.
    /// @return shares Shares minted.
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /// @notice Claim an async deposit by calling ERC-4626 mint.
    /// @dev Overload per ERC-7540. MUST revert unless msg.sender == controller or operator.
    /// @param shares Shares to mint to receiver.
    /// @param receiver Recipient of shares.
    /// @param controller Controller discriminating the claim when sender is operator.
    /// @return assets Assets consumed.
    function mint(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    /// @notice Assume control of shares from owner and submit an async redeem Request.
    /// @dev MUST emit RedeemRequest. MUST revert if all shares cannot be requested.
    /// @param shares Amount of shares to request redemption for.
    /// @param controller Controller of the Request (msg.sender unless operator-approved).
    /// @param owner Owner of the shares; MUST be msg.sender unless operator-approved.
    /// @return requestId Discriminator paired with controller (see Request Ids semantics).
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /// @notice Amount of requested shares in Pending state for controller/requestId.
    /// @dev MUST NOT include amounts in Claimable; MUST NOT vary by caller.
    /// @param requestId Request identifier.
    /// @param controller Controller address.
    /// @return pendingShares Amount in Pending.
    function pendingRedeemRequest(uint256 requestId, address controller) external returns (uint256 pendingShares);

    /// @notice Amount of requested shares in Claimable state for controller/requestId.
    /// @dev MUST NOT include amounts in Pending; MUST NOT vary by caller.
    /// @param requestId Request identifier.
    /// @param controller Controller address.
    /// @return claimableShares Amount in Claimable.
    function claimableRedeemRequest(uint256 requestId, address controller) external returns (uint256 claimableShares);

    /// @notice Claim an async redemption by calling ERC-4626 redeem.
    /// @dev Overload per ERC-7540. MUST revert unless msg.sender == controller or operator.
    /// @param shares Shares to redeem.
    /// @param receiver Recipient of assets.
    /// @param controller Controller discriminating the claim when sender is operator.
    /// @return assets Assets returned.
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    /// @notice Claim an async redemption by calling ERC-4626 withdraw.
    /// @dev Overload per ERC-7540. MUST revert unless msg.sender == controller or operator.
    /// @param assets Assets to withdraw.
    /// @param receiver Recipient of assets.
    /// @param controller Controller discriminating the claim when sender is operator.
    /// @return shares Shares burned.
    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /// @notice Returns true if operator is approved for controller.
    /// @param controller Controller address.
    /// @param operator Operator address.
    /// @return status Operator approval status.
    function isOperator(address controller, address operator) external view returns (bool);

    /// @notice Approve or revoke an operator for the msg.sender (controller).
    /// @dev MUST set operator status, emit OperatorSet, and return true.
    /// @param operator Operator to set.
    /// @param approved New approval status.
    /// @return success True.
    function setOperator(address operator, bool approved) external returns (bool);
}
