// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Math } from "../../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { RoycoAuth } from "../../../../auth/RoycoAuth.sol";
import { IAsyncJTRedemptionDelayKernel } from "../../../../interfaces/kernel/IAsyncJTRedemptionDelayKernel.sol";
import { ExecutionModel, IRoycoKernel } from "../../../../interfaces/kernel/IRoycoKernel.sol";
import { ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID } from "../../../../libraries/Constants.sol";
import { AssetClaims } from "../../../../libraries/Types.sol";
import { Operation, RequestRedeemSharesBehavior, SyncedAccountingState, TrancheType } from "../../../../libraries/Types.sol";
import { NAV_UNIT, UnitsMathLib, toNAVUnits, toUint256 } from "../../../../libraries/Units.sol";
import { RoycoKernel } from "../../RoycoKernel.sol";

/// @title RedemptionDelayJTKernel
/// @notice Abstract base contract for a junior tranche redemption delay kernel
abstract contract RedemptionDelayJTKernel is IAsyncJTRedemptionDelayKernel {
    using Math for uint256;
    using UnitsMathLib for NAV_UNIT;

    /// @dev Storage slot for RedemptionDelayJTKernelState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.RedemptionDelayJTKernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_ASYNC_JT_REDEMPTION_DELAY_KERNEL_STORAGE_SLOT = 0xded0c80c14aecd5426bd643f18df17d9cea228e72fcaefe1b139ffca90913500;

    /// @notice Thrown when the function is not implemented
    error PREVIEW_REDEEM_DISABLED_FOR_ASYNC_REDEMPTION();

    /**
     * @notice Initializes a kernel that employs a redemption delay on its junior tranche LPs
     * @param _jtRedemptionDelaySeconds The delay in seconds between a junior tranche LP requesting a redemption and being able to execute it
     */
    function __RedemptionDelay_JT_Kernel_init_unchained(uint256 _jtRedemptionDelaySeconds) internal onlyInitializing {
        _getRedemptionDelayJTKernelState().jtRedemptionDelaySeconds = _jtRedemptionDelaySeconds;
    }

    // =============================
    // ERC7540 Asynchronous Flow Functions
    // =============================

    /// @inheritdoc IAsyncJTRedemptionDelayKernel
    function jtPendingRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        checkJTRedemptionRequestId(_requestId)
        returns (uint256 pendingShares)
    {
        Redemption storage redemption = _getRedemptionDelayJTKernelState().controllerToRedemptionState[_controller];
        // If the redemption is canceled or the request is claimable, no shares are still in a pending state
        if (redemption.isCanceled || redemption.redemptionAllowedAtTimestamp >= block.timestamp) return 0;
        // The shares in the controller's redemption request are still pending
        pendingShares = redemption.totalJTSharesToRedeem;
    }

    /// @inheritdoc IAsyncJTRedemptionDelayKernel
    function jtClaimableRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        checkJTRedemptionRequestId(_requestId)
        returns (uint256 claimableShares)
    {
        claimableShares = _jtClaimableRedeemRequest(_controller);
    }

    // =============================
    // ERC7887 Cancelation functions
    // =============================

    /// @inheritdoc IAsyncJTRedemptionDelayKernel
    function jtCancelRedeemRequest(uint256 _requestId, address _controller) external whenNotPaused onlyJuniorTranche checkJTRedemptionRequestId(_requestId) {
        Redemption storage redemption = _getRedemptionDelayJTKernelState().controllerToRedemptionState[_controller];
        // Cannot cancel an already cancelled request
        require(!redemption.isCanceled, REDEMPTION_ALREADY_CANCELED());
        // Mark this request as canceled
        redemption.isCanceled = true;
    }

    /// @inheritdoc IAsyncJTRedemptionDelayKernel
    function jtPendingCancelRedeemRequest(uint256, address) external view returns (bool isPending) {
        // Cancelation requests are always processed instantly, so there is never a pending cancelation
        isPending = false;
    }

    /// @inheritdoc IAsyncJTRedemptionDelayKernel
    function jtClaimableCancelRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        checkJTRedemptionRequestId(_requestId)
        returns (uint256 shares)
    {
        RedemptionDelayJTKernelState storage $ = _getRedemptionDelayJTKernelState();
        // If the redemption is not canceled, there are no shares to claim
        if (!$.controllerToRedemptionState[_controller].isCanceled) return 0;
        // Return the shares for the redemption request that has been requested to be cancelled
        shares = $.controllerToRedemptionState[_controller].totalJTSharesToRedeem;
    }

    /// @inheritdoc IAsyncJTRedemptionDelayKernel
    function jtClaimCancelRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        whenNotPaused
        onlyJuniorTranche
        checkJTRedemptionRequestId(_requestId)
        returns (uint256 shares)
    {
        RedemptionDelayJTKernelState storage $ = _getRedemptionDelayJTKernelState();
        Redemption storage redemption = $.controllerToRedemptionState[_controller];
        // Cannot claim a non-existant cancellation request
        require(redemption.isCanceled, REDEMPTION_NOT_CANCELED());
        // Check that their is a redemption
        require((shares = redemption.totalJTSharesToRedeem) != 0, MUST_CLAIM_NON_ZERO_SHARES());
        // Clear all redemption state since cancellation has been processed
        delete $.controllerToRedemptionState[_controller];
    }

    /**
     * @notice Accounts for the total JT shares claimed from a claimable redemption request
     * @notice Used by concrete JT kernels on redeem execution to determine what NAV to liquidate for the user
     * @param _controller The controller that is allowed to operate the claim
     * @param _currentJTEffectiveNAV The current effective NAV of JT
     * @param _sharesToRedeem The amount of JT shares to redeem
     * @param _totalShares The total number of JT shares to redeem
     * @return navOfSharesToRedeem The NAV of the shares
     */
    function _processClaimableRedeemRequest(
        address _controller,
        NAV_UNIT _currentJTEffectiveNAV,
        uint256 _sharesToRedeem,
        uint256 _totalShares
    )
        internal
        returns (NAV_UNIT navOfSharesToRedeem)
    {
        // Ensure that the shares to redeem are actually claimable right now
        uint256 claimableShares = _jtClaimableRedeemRequest(_controller);
        require(_sharesToRedeem <= claimableShares, INSUFFICIENT_CLAIMABLE_SHARES(_sharesToRedeem, claimableShares));

        // JT LPs are not entitled to any JT upside during the redemption delay
        // However, they are liable for providing coverage to ST LPs during the redemption delay
        RedemptionDelayJTKernelState storage $ = _getRedemptionDelayJTKernelState();
        Redemption storage redemption = $.controllerToRedemptionState[_controller];

        // Calculate the current NAV of the shares being redeemed
        NAV_UNIT redemptionValueAtCurrentNAV = _redemptionValue(_currentJTEffectiveNAV, _sharesToRedeem, _totalShares);
        // Calculate the NAV of the shares at redemption request time as a ratio of the shares being redeemed and the total initially requested to be redeemed
        NAV_UNIT redemptionValueAtRequest = redemption.redemptionValueAtRequest.mulDiv(_sharesToRedeem, redemption.totalJTSharesToRedeem, Math.Rounding.Floor);
        // The NAV to liquidate for the shares to redeem is minimum of the value now and the value at request: ensures JT gets no upside but incurs any downside
        navOfSharesToRedeem = UnitsMathLib.min(redemptionValueAtCurrentNAV, redemptionValueAtRequest);

        // Update the request accounting based on the shares being redeemed
        uint256 sharesRemaining = redemption.totalJTSharesToRedeem - _sharesToRedeem;
        if (sharesRemaining != 0) {
            // Update the redemption value at request for the remaining shares
            redemption.redemptionValueAtRequest = redemption.redemptionValueAtRequest - redemptionValueAtRequest;
            redemption.totalJTSharesToRedeem = sharesRemaining;
        } else {
            // If there are no remaining shares, delete the controller's redemption
            delete $.controllerToRedemptionState[_controller];
        }
    }

    /**
     * @notice Returns the amount of JT shares claimable from a redemption request
     * @param _controller The controller that is allowed to operate the claim
     * @return claimableShares The amount of JT shares claimable from the redemption request
     */
    function _jtClaimableRedeemRequest(address _controller) internal view returns (uint256 claimableShares) {
        Redemption storage redemption = _getRedemptionDelayJTKernelState().controllerToRedemptionState[_controller];
        // If the redemption is canceled or not claimable, no shares are claimable
        if (redemption.isCanceled || redemption.redemptionAllowedAtTimestamp < block.timestamp) return 0;
        // Return the shares in the request
        claimableShares = redemption.totalJTSharesToRedeem;
    }

    /**
     * @notice Computes the value of a redemption request
     * @param _currentJTEffectiveNAV The current effective NAV of JT
     * @param _shares The amount of JT shares to redeem
     * @param _totalShares The total number of JT shares in the tranche, including the virtual shares
     * @return value The value of the redemption request
     */
    function _redemptionValue(NAV_UNIT _currentJTEffectiveNAV, uint256 _shares, uint256 _totalShares) internal pure returns (NAV_UNIT value) {
        return _currentJTEffectiveNAV.mulDiv(_shares, _totalShares, Math.Rounding.Floor);
    }

    /**
     * @notice Returns a storage pointer to the RedemptionDelayJTKernelState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer to the base async redemption delay kernel
     */
    function _getRedemptionDelayJTKernelState() private pure returns (RedemptionDelayJTKernelState storage $) {
        assembly ("memory-safe") {
            $.slot := BASE_ASYNC_JT_REDEMPTION_DELAY_KERNEL_STORAGE_SLOT
        }
    }
}
