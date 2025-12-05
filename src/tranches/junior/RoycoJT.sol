// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAsyncJTDepositKernel } from "../../interfaces/kernel/IAsyncJTDepositKernel.sol";
import { IAsyncJTWithdrawalKernel } from "../../interfaces/kernel/IAsyncJTWithdrawalKernel.sol";
import { IRoycoBaseKernel } from "../../interfaces/kernel/IRoycoBaseKernel.sol";
import { IRoycoJuniorTranche, IRoycoTranche } from "../../interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { RoycoTrancheStorageLib } from "../../libraries/RoycoTrancheStorageLib.sol";
import { Action, TrancheDeploymentParams } from "../../libraries/Types.sol";
import { BaseRoycoTranche, ERC4626Upgradeable, IERC20, Math } from "../BaseRoycoTranche.sol";

// TODO: ST and JT base asset can have different decimals
contract RoycoJT is IRoycoJuniorTranche, BaseRoycoTranche {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Thrown when the caller is not the corresponding senior tranche
    error ONLY_SENIOR_TRANCHE();

    /**
     * @notice Initializes the Royco junior tranche
     * @param _jtParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the junior tranche
     * @param _asset The underlying asset for the tranche
     * @param _owner The initial owner of the tranche
     * @param _marketId The identifier of the Royco market this tranche is linked to
     * @param _seniorTranche The address of the senior tranche corresponding to this junior tranche
     */
    function initialize(
        TrancheDeploymentParams calldata _jtParams,
        address _asset,
        address _owner,
        bytes32 _marketId,
        address _seniorTranche
    )
        external
        initializer
    {
        // Initialize the Royco Junior Tranche
        __RoycoTranche_init(_jtParams, _asset, _owner, _marketId, _seniorTranche);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Returns the junior tranche's effective total assets after factoring in any covered losses and yield distribution
    function totalAssets() public view override(BaseRoycoTranche) returns (uint256 jtEffectiveNAV) {
        (,,, jtEffectiveNAV) = _previewSyncTrancheNAVs();
    }

    /// @inheritdoc BaseRoycoTranche
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        override(BaseRoycoTranche)
        onlyCallerOrOperator(_controller)
        returns (uint256 shares)
    {
        // Assert that the assets being withdrawn by the user fall under the permissible limits
        uint256 maxWithdrawableAssets = maxWithdraw(_controller);
        require(_assets <= maxWithdrawableAssets, ERC4626ExceededMaxWithdraw(_controller, _assets, maxWithdrawableAssets));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, _assets, (shares = super.previewWithdraw(_assets)));

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        _callKernelWithdraw(_assets, msg.sender, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function redeem(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        override(BaseRoycoTranche)
        onlyCallerOrOperator(_controller)
        returns (uint256 assets)
    {
        // Assert that the shares being redeeemed by the user fall under the permissible limits
        uint256 maxRedeemableShares = maxRedeem(_controller);
        require(_shares <= maxRedeemableShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxRedeemableShares));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, (assets = super.previewRedeem(_shares)), _shares);

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        _callKernelWithdraw(assets, msg.sender, _receiver);
    }

    /// @inheritdoc IRoycoJuniorTranche
    function coverLosses(uint256 _assets, address _receiver) external returns (uint256 requestId) {
        // Ensure the caller is the senio
        require(msg.sender == RoycoTrancheStorageLib._getRoycoTrancheStorage().complementTranche, ONLY_SENIOR_TRANCHE());
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev No inherent tranche enforced cap on junior tranche deposits
    function _getTrancheDepositCapacity() internal pure override(BaseRoycoTranche) returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc BaseRoycoTranche
     * @notice Computes the assets that can be withdrawn from the junior tranche without violating the coverage condition
     * @dev Coverage condition: JT_NAV >= (JT_NAV + ST_NAV) * COV_%
     *      This is capped out when: JT_NAV == (JT_NAV + ST_NAV) * COV_%
     * @dev Solving for the max amount of assets we can withdraw from the junior tranche, x:
     *      (JT_NAV - x) = ((JT_NAV - x) + ST_NAV) * COV_%
     *      x = JT_NAV - ((ST_NAV * COV_%) / (100% - COV_%))
     */
    function _getTrancheWithdrawalCapacity() internal view override(BaseRoycoTranche) returns (uint256) {
        // Compute x, clipped to 0 to prevent underflow
        return Math.saturatingSub(_getJuniorTrancheNAV(), _computeMinJuniorTrancheNAV());
    }

    /// @inheritdoc BaseRoycoTranche
    function _getJuniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return _getSelfNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _getSeniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoTranche(RoycoTrancheStorageLib._getRoycoTrancheStorage().complementTranche).getNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelMaxDeposit(address _receiver) internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtMaxDeposit(_receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelMaxWithdraw(address _owner) internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtMaxWithdraw(_owner);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelGetNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).getJTRawNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelDeposit(uint256 _assets, address _caller, address _receiver) internal override(BaseRoycoTranche) {
        IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtDeposit(_assets, _caller, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelWithdraw(uint256 _assets, address _caller, address _receiver) internal override(BaseRoycoTranche) {
        IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtWithdraw(_assets, _caller, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelRequestDeposit(uint256 _assets, address _controller) internal override(BaseRoycoTranche) returns (uint256 requestId) {
        return IAsyncJTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtRequestDeposit(msg.sender, _assets, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncJTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtPendingDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncJTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtClaimableDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelRequestRedeem(uint256 _assets, uint256 _shares, address _controller) internal override(BaseRoycoTranche) returns (uint256 requestId) {
        return IAsyncJTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtRequestWithdrawal(msg.sender, _assets, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncJTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtPendingWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncJTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtClaimableWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelCancelDepositRequest(uint256 _requestId, address _controller) internal override(BaseRoycoTranche) {
        IAsyncJTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtCancelDepositRequest(msg.sender, _requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingCancelDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (bool) {
        return IAsyncJTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtPendingCancelDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableCancelDepositRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncJTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtClaimableCancelDepositRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelCancelRedeemRequest(uint256 _requestId, address _controller) internal override(BaseRoycoTranche) {
        IAsyncJTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtCancelWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelPendingCancelRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (bool) {
        return IAsyncJTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtPendingCancelWithdrawalRequest(_requestId, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelClaimableCancelRedeemRequest(uint256 _requestId, address _controller) internal view override(BaseRoycoTranche) returns (uint256) {
        return IAsyncJTWithdrawalKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).jtClaimableCancelWithdrawalRequest(_requestId, _controller);
    }
}
