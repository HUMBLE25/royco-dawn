// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAsyncSTDepositKernel } from "../../interfaces/kernel/IAsyncSTDepositKernel.sol";
import { IAsyncSTWithdrawalKernel } from "../../interfaces/kernel/IAsyncSTWithdrawalKernel.sol";
import { IRoycoBaseKernel } from "../../interfaces/kernel/IRoycoBaseKernel.sol";
import { IRoycoTranche } from "../../interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { RoycoTrancheStorageLib } from "../../libraries/RoycoTrancheStorageLib.sol";
import { TrancheDeploymentParams } from "../../libraries/Types.sol";
import { BaseRoycoTranche, Math } from "../BaseRoycoTranche.sol";

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

    /// @inheritdoc BaseRoycoTranche
    /// @dev Post-checks the coverage condition, ensuring that the new senior capital isn't undercovered
    function deposit(uint256 _assets, address _receiver, address _controller) public override(BaseRoycoTranche) returns (uint256 shares) {
        return super.deposit(_assets, _receiver, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Post-checks the coverage condition, ensuring that the new senior capital isn't undercovered
    function mint(uint256 _shares, address _receiver, address _controller) public override(BaseRoycoTranche) returns (uint256 assets) {
        return super.mint(_shares, _receiver, _controller);
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
        // Assert that the assets being withdrawn by the user fall under the permissible limit
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
        // Assert that the shares being redeeemed by the user fall under the permissible limit
        uint256 maxRedeemableShares = maxRedeem(_controller);
        require(_shares <= maxRedeemableShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxRedeemableShares));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, (assets = super.previewRedeem(_shares)), _shares);

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        _callKernelWithdraw(assets, msg.sender, _receiver);
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
        return Math.saturatingSub(totalCoveredAssets, jtRawNAV).saturatingSub(_getSelfNAV());
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
        return _getSelfNAV();
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
    function _callKernelDeposit(uint256 _assets, address _caller, address _receiver) internal override(BaseRoycoTranche) {
        IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stDeposit(_assets, _caller, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelWithdraw(uint256 _assets, address _caller, address _receiver) internal override(BaseRoycoTranche) {
        IRoycoBaseKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stWithdraw(_assets, _caller, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function _callKernelRequestDeposit(uint256 _assets, address _controller) internal override(BaseRoycoTranche) returns (uint256 requestId) {
        return IAsyncSTDepositKernel(RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel).stRequestDeposit(msg.sender, _assets, _controller);
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
    function _callKernelRequestRedeem(uint256 _assets, uint256 _shares, address _controller) internal override(BaseRoycoTranche) returns (uint256 requestId) {
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
