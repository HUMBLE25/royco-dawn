// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @notice Initialization parameters for the Royco Kernel
 * @custom:field seniorTranche - The address of the Royco senior tranche associated with this kernel
 * @custom:field juniorTranche - The address of the Royco junior tranche associated with this kernel
 * @custom:field accountant - The address of the Royco accountant used to perform per operation accounting for this kernel
 * @custom:field protocolFeeRecipient - The market's protocol fee recipient
 * @custom:field redemptionAllowedAtTimestamp - The timestamp at which the redemption request is allowed to be claimed
 * @custom:field jtRedemptionDelaySeconds - The redemption delay in seconds that a JT LP has to wait between requesting and executing a redemption
 */
struct RoycoKernelInitParams {
    address seniorTranche;
    address juniorTranche;
    address accountant;
    address protocolFeeRecipient;
    uint32 jtRedemptionDelaySeconds;
}

/**
 * @notice Storage state for the Royco Kernel
 * @custom:storage-location erc7201:Royco.storage.RoycoKernelState
 * @custom:field seniorTranche - The address of the Royco senior tranche associated with this kernel
 * @custom:field stAsset - The address of the asset that ST is denominated in: constitutes the ST's tranche units (type and precision)
 * @custom:field juniorTranche - The address of the Royco junior tranche associated with this kernel
 * @custom:field jtAsset - The address of the asset that JT is denominated in: constitutes the ST's tranche units (type and precision)
 * @custom:field protocolFeeRecipient - The market's configured protocol fee recipient
 * @custom:field accountant - The address of the Royco accountant used to perform per operation accounting for this kernel
 * @custom:field jtRedemptionDelaySeconds - The redemption delay in seconds that a JT LP has to wait between requesting and executing a redemption
 * @custom:field redemptions - A mapping between a controller and their redemption request state
 */
struct RoycoKernelState {
    address seniorTranche;
    address stAsset;
    address juniorTranche;
    address jtAsset;
    address protocolFeeRecipient;
    address accountant;
    uint32 jtRedemptionDelaySeconds;
    mapping(address controller => RedemptionRequest jtRedemptionRequest) jtControllerToRedemptionState;
}

/**
 * @notice The state of a JT LP's redemption request
 * @custom:field isCanceled - A boolean indicating whether the redemption request has been canceled
 * @custom:field redemptionAllowedAtTimestamp - The timestamp at which the redemption request is allowed to be claimed/executed
 * @custom:field totalJTSharesToRedeem - The total number of JT shares to redeem
 * @custom:field redemptionValueAtRequest - The NAV of the redemption request at the time it was requested
 */
struct RedemptionRequest {
    bool isCanceled;
    uint32 redemptionAllowedAtTimestamp;
    uint256 totalJTSharesToRedeem;
    NAV_UNIT redemptionValueAtRequest;
}

/// @title RoycoKernelStorageLib
/// @notice Library for managing Royco Kernel storage using the ERC7201 pattern
library RoycoKernelStorageLib {
    /// @dev Storage slot for RoycoKernelState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.RoycoKernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_KERNEL_STORAGE_SLOT = 0xf8fc0d016168fef0a165a086b5a5dc3ffa533689ceaf1369717758ae5224c600;

    /// @notice Returns a storage pointer to the RoycoKernelState storage
    /// @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
    /// @return $ Storage pointer to the kernel's state
    function _getRoycoKernelStorage() internal pure returns (RoycoKernelState storage $) {
        assembly ("memory-safe") {
            $.slot := BASE_KERNEL_STORAGE_SLOT
        }
    }

    /// @notice Initializes the kernel state
    /// @param _params The initialization parameters for the kernel
    function __RoycoKernel_init(RoycoKernelInitParams memory _params, address _stAsset, address _jtAsset) internal {
        // Set the initial state of the kernel
        RoycoKernelState storage $ = _getRoycoKernelStorage();
        $.seniorTranche = _params.seniorTranche;
        $.stAsset = _stAsset;
        $.juniorTranche = _params.juniorTranche;
        $.jtAsset = _jtAsset;
        $.protocolFeeRecipient = _params.protocolFeeRecipient;
        $.accountant = _params.accountant;
        $.jtRedemptionDelaySeconds = _params.jtRedemptionDelaySeconds;
    }
}
