// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IAsyncSTDepositKernel } from "../../interfaces/kernel/IAsyncSTDepositKernel.sol";
import { IAsyncSTWithdrawalKernel } from "../../interfaces/kernel/IAsyncSTWithdrawalKernel.sol";
import { IBaseKernel } from "../../interfaces/kernel/IBaseKernel.sol";
import { IRoycoTranche } from "../../interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { RoycoTrancheStorageLib } from "../../libraries/RoycoTrancheStorageLib.sol";
import { TrancheDeploymentParams } from "../../libraries/Types.sol";
import { Action, BaseRoycoTranche, Math } from "../BaseRoycoTranche.sol";

// TODO: ST and JT base asset can have different decimals
contract RoycoST is BaseRoycoTranche {
    using Math for uint256;

    /**
     * @notice Initializes the Royco senior tranche
     * @param _stParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the senior tranche
     * @param _asset The underlying asset for the tranche
     * @param _owner The initial owner of the tranche
     * @param _marketId The identifier of the Royco market this tranche is linked to
     * @param _juniorTranche The address of the junior tranche corresponding to this senior tranche
     */
    function initialize(
        TrancheDeploymentParams calldata _stParams,
        address _asset,
        address _owner,
        bytes32 _marketId,
        address _juniorTranche
    )
        external
        initializer
    {
        // Initialize the Royco Senior Tranche
        __RoycoTranche_init(_stParams, _asset, _owner, _marketId, _juniorTranche);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Returns the senior tranche's effective total assets after factoring in any covered losses and yield distribution
    function totalAssets() public view override(BaseRoycoTranche) returns (uint256 stEffectiveNAV) {
        (,, stEffectiveNAV,) = _previewSyncTrancheNAVs();
    }

    /**
     * @inheritdoc BaseRoycoTranche
     * @notice Computes the assets that can be deposited into the senior tranche without violating the coverage condition
     * @dev coverage condition: JT_NAV >= (JT_NAV + ST_NAV) * COV_%
     *      This is capped out when: JT_NAV == (JT_NAV + ST_NAV) * COV_%
     * @dev Solving for the max amount of assets we can deposit into the senior tranche, x:
     *      JT_NAV = (JT_NAV + (ST_NAV + x)) * COV_%
     *      x = (JT_NAV / COV_%) - JT_NAV - ST_NAV
     */
    function _getTrancheDepositCapacity() internal view override(BaseRoycoTranche) returns (uint256) {
        // Retrieve the junior tranche net asset value
        uint256 jtRawNAV = _getJuniorTrancheNAV();
        if (jtRawNAV == 0) return 0;

        // Compute the total assets currently covered by the junior tranche
        // Round in favor of the senior tranche
        uint256 totalCoveredAssets = jtRawNAV.mulDiv(ConstantsLib.WAD, RoycoTrancheStorageLib._getRoycoTrancheStorage().coverageWAD, Math.Rounding.Floor);

        // Compute x, clipped to 0 to prevent underflow
        return Math.saturatingSub(totalCoveredAssets, jtRawNAV).saturatingSub(_callKernelGetNAV());
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev No inherent tranche enforced cap on senior tranche withdrawals
    function _getTrancheWithdrawalCapacity() internal pure override(BaseRoycoTranche) returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc BaseRoycoTranche
    function _getJuniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoTranche(RoycoTrancheStorageLib._getRoycoTrancheStorage().complementTranche).getNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _getSeniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return _callKernelGetNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelMaxDeposit(address _receiver) internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stMaxDeposit(_receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelMaxWithdraw(address _owner) internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stMaxWithdraw(_owner);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelGetNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).getSTRawNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelDeposit(
        uint256 _assets,
        address _caller,
        address _receiver
    )
        internal
        override(BaseRoycoTranche)
        returns (uint256 fractionOfTotalAssetsAllocatedWAD)
    {
        IRoycoBaseKernel kernel = IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel);
        // If the deposit is synchronous, the assets are expected to be transferred from the caller to the tranche now.
        if (_isSync(Action.DEPOSIT)) {
            IERC20(asset()).approve(address(kernel), _assets);
        }
        return kernel.stDeposit(_assets, _caller, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelWithdraw(
        uint256 _assets,
        address _caller,
        address _receiver
    )
        internal
        override(BaseRoycoTranche)
        returns (uint256 fractionOfTotalAssetsRedeemedWAD, uint256 assetsRedeemed)
    {
        (fractionOfTotalAssetsRedeemedWAD, assetsRedeemed) =
            IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stWithdraw(_assets, _caller, _receiver);
        return (fractionOfTotalAssetsRedeemedWAD, assetsRedeemed);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelRequestDeposit(uint256 _assets, address _controller) internal override(BaseRoycoTranche) returns (uint256 requestId) {
        IAsyncSTDepositKernel kernel = IAsyncSTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel);
        // If the deposit is asynchronous, the assets are expected to be transferred from the caller to the tranche on the request.
        IERC20(asset()).approve(address(kernel), _assets);
        return kernel.stRequestDeposit(msg.sender, _assets, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncSTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stPendingDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncSTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stClaimableDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelRequestRedeem(uint256 _assets, address _controller) internal override(BaseRoycoTranche) returns (uint256 requestId) {
        return IAsyncSTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stRequestWithdrawal(msg.sender, _assets, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncSTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stPendingWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncSTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stClaimableWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelCancelDepositRequest(uint256 _requestId, address _controller) internal override(BaseRoycoTranche) {
        IAsyncSTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stCancelDepositRequest(msg.sender, _requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingCancelDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (bool) {
        return IAsyncSTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stPendingCancelDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableCancelDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncSTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stClaimableCancelDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelCancelRedeemRequest(uint256 _requestId, address _controller) internal override(BaseRoycoTranche) {
        IAsyncSTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stCancelWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingCancelRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (bool) {
        return IAsyncSTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stPendingCancelWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableCancelRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncSTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stClaimableCancelWithdrawalRequest(_requestId, _controller);
    }
}
