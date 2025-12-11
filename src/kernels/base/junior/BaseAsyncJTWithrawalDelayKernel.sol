// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { RoycoAuth } from "../../../auth/RoycoAuth.sol";
import { RoycoRoles } from "../../../auth/RoycoRoles.sol";
import { IAsyncJTWithdrawalKernel } from "../../../interfaces/kernel/IAsyncJTWithdrawalKernel.sol";
import { IBaseKernel } from "../../../interfaces/kernel/IBaseKernel.sol";
import { BaseKernel } from "../BaseKernel.sol";

/// @title BaseAsyncJTWithrawalDelayKernel
/// @notice Abstract base contract for the junior tranche withdrawal delay kernel
abstract contract BaseAsyncJTWithrawalDelayKernel is IAsyncJTWithdrawalKernel, IBaseKernel, RoycoAuth, BaseKernel {
    using Math for uint256;

    // keccak256(abi.encode(uint256(keccak256("Royco.storage.BaseAsyncJTWithdrawalDelayKernel")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BaseAsyncJTWithdrawalDelayKernelStorageLocation = 0xb5c6c83047900617b0d8e0a777db642d7504e41a6e0a65096bced63526c1bf00;

    /// @dev Emitted when the withdrawal delay is updated
    event WithdrawalDelayUpdated(uint256 withdrawalDelaySeconds);
    /// @dev Emitted when a withdrawal request is made
    event WithdrawalRequest(address indexed controller, uint256 indexed requestId, uint256 shares);
    /// @dev Emitted when a withdrawal request is claimed
    event WithdrawalClaimed(address indexed controller, uint256 shares);

    /// @notice Thrown when the withdrawal delay is zero
    error INVALID_WITHDRAWAL_DELAY_SECONDS(uint256 withdrawalDelaySeconds);
    /// @notice Thrown when the total shares to withdraw is less than the shares to redeem
    error INSUFFICIENT_SHARES(uint256 sharesToRedeem, uint256 totalSharesToWithdraw);
    /// @notice Thrown when the withdrawal is not allowed
    error WITHDRAWAL_NOT_ALLOWED(uint256 withdrawalAllowedAtTimestamp);

    /// @custom:storage-location erc7201:Royco.storage.BaseAsyncJTWithdrawalDelayKernelState
    struct BaseAsyncJTWithdrawalDelayKernelState {
        uint256 withdrawalDelaySeconds;
        mapping(address controller => Withdrawal withdrawal) controllerWithdrawals;
    }

    struct Withdrawal {
        uint256 totalJTSharesToWithdraw;
        uint256 withdrawalAllowedAtTimestamp;
    }

    function __BaseAsyncJTWithrawalDelayKernel_init(uint256 _withdrawalDelaySeconds) internal onlyInitializing {
        __BaseAsyncJTWithrawalDelayKernel_init_unchained(_withdrawalDelaySeconds);
    }

    function __BaseAsyncJTWithrawalDelayKernel_init_unchained(uint256 _withdrawalDelaySeconds) internal onlyInitializing {
        require(_withdrawalDelaySeconds > 0, INVALID_WITHDRAWAL_DELAY_SECONDS(_withdrawalDelaySeconds));
        __BaseAsyncJTWithrawalDelayKernel_init(_withdrawalDelaySeconds);
    }

    /// @inheritdoc IAsyncJTWithdrawalKernel
    function jtRequestWithdrawal(address _caller, uint256 _shares, uint256, address _controller) external returns (uint256 requestId) {
        BaseAsyncJTWithdrawalDelayKernelState storage $ = _getBaseAsyncJTWithdrawalDelayKernelState();
        uint256 totalSharesToWithdraw = ($.controllerWithdrawals[_controller].totalJTSharesToWithdraw += _shares);
        $.controllerWithdrawals[_controller].withdrawalAllowedAtTimestamp = block.timestamp + $.withdrawalDelaySeconds;
        emit WithdrawalRequest(_controller, requestId, totalSharesToWithdraw);
        return 0; // We support a single withdrawal request per controller
    }

    /// @inheritdoc IAsyncJTWithdrawalKernel
    function jtPendingWithdrawalRequest(uint256 _requestId, uint256 _totalShares, address _controller) external view returns (uint256 pendingAssets) {
        BaseAsyncJTWithdrawalDelayKernelState storage $ = _getBaseAsyncJTWithdrawalDelayKernelState();

        // If the withdrawal is not allowed yet, return 0
        if ($.controllerWithdrawals[_controller].withdrawalAllowedAtTimestamp >= block.timestamp) {
            return 0;
        }

        uint256 totalSharesToWithdraw = $.controllerWithdrawals[_controller].totalJTSharesToWithdraw;
        return getJTTotalEffectiveAssets().mulDiv(totalSharesToWithdraw, _totalShares, Math.Rounding.Floor);
    }

    /// @inheritdoc IAsyncJTWithdrawalKernel
    function jtClaimableWithdrawalRequest(uint256 _requestId, uint256 _totalShares, address _controller) external view returns (uint256 claimableAssets) {
        BaseAsyncJTWithdrawalDelayKernelState storage $ = _getBaseAsyncJTWithdrawalDelayKernelState();

        // If the withdrawal is not allowed yet, return 0
        if ($.controllerWithdrawals[_controller].withdrawalAllowedAtTimestamp < block.timestamp) {
            return 0;
        }

        uint256 totalSharesToWithdraw = $.controllerWithdrawals[_controller].totalJTSharesToWithdraw;
        return getJTTotalEffectiveAssets().mulDiv(totalSharesToWithdraw, _totalShares, Math.Rounding.Floor);
    }

    /// @inheritdoc IAsyncJTWithdrawalKernel
    function jtClaimableCancelWithdrawalRequest(uint256 _requestId, address _controller) external view returns (uint256 assets) {
        // TODO: Implement this
    }

    /// @inheritdoc IAsyncJTWithdrawalKernel
    function jtCancelWithdrawalRequest(uint256 _requestId, address _controller) external {
        // TODO: Implement this
    }

    /// @inheritdoc IAsyncJTWithdrawalKernel
    function jtPendingCancelWithdrawalRequest(uint256 _requestId, address _controller) external view returns (bool isPending) {
        // TODO: Implement this
    }

    function getJTTotalEffectiveAssets() public view virtual override(IBaseKernel) returns (uint256);

    function setWithdrawalDelay(uint256 _withdrawalDelaySeconds) external onlyRole(RoycoRoles.KERNEL_ADMIN_ROLE) {
        _getBaseAsyncJTWithdrawalDelayKernelState().withdrawalDelaySeconds = _withdrawalDelaySeconds;
        emit WithdrawalDelayUpdated(_withdrawalDelaySeconds);
    }

    function withdrawalDelay() external view returns (uint256) {
        return _getBaseAsyncJTWithdrawalDelayKernelState().withdrawalDelaySeconds;
    }

    /// @notice Accounts for the total JT shares claimed from a claimable withdrawal request
    /// @param _controller The controller that is allowed to operate the claim
    /// @param _jtSharesToRedeem The amount of JT shares to redeem
    function _processClaimableRedeemRequest(address _controller, uint256 _jtSharesToRedeem) internal {
        BaseAsyncJTWithdrawalDelayKernelState storage $ = _getBaseAsyncJTWithdrawalDelayKernelState();
        Withdrawal storage withdrawal = $.controllerWithdrawals[_controller];
        uint256 totalSharesToWithdraw = withdrawal.totalJTSharesToWithdraw;

        // Assert that the total shares to withdraw is greater than or equal to the shares to redeem
        require(totalSharesToWithdraw >= _jtSharesToRedeem, INSUFFICIENT_SHARES(_jtSharesToRedeem, totalSharesToWithdraw));
        // Assert that the withdrawal is allowed
        uint256 withdrawalAllowedAtTimestamp = withdrawal.withdrawalAllowedAtTimestamp;
        require(withdrawalAllowedAtTimestamp <= block.timestamp, WITHDRAWAL_NOT_ALLOWED(withdrawalAllowedAtTimestamp));

        // If the total shares to withdraw is equal to the shares to redeem, delete the controller's withdrawal
        // Otherwise, subtract the shares to redeem from the total shares to withdraw
        if (totalSharesToWithdraw == _jtSharesToRedeem) {
            delete $.controllerWithdrawals[_controller];
        } else {
            withdrawal.totalJTSharesToWithdraw -= _jtSharesToRedeem;
        }
        emit WithdrawalClaimed(_controller, _jtSharesToRedeem);
    }

    function _getBaseAsyncJTWithdrawalDelayKernelState() private pure returns (BaseAsyncJTWithdrawalDelayKernelState storage $) {
        assembly ("memory-safe") {
            $.slot := BaseAsyncJTWithdrawalDelayKernelStorageLocation
        }
    }
}
