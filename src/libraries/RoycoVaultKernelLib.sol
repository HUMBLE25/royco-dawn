// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultKernel } from "../interfaces/IRoycoVaultKernel.sol";

// todo: document

library RoycoVaultKernelLib {
    error KernelCallFailed(bytes callData, bytes returnData);

    function _initialize(address _kernel, bytes calldata _params) internal {
        _delegateCallKernel(_kernel, _params);
    }

    function _totalAssets(address _kernel, address _asset) internal view returns (uint256) {
        return IRoycoVaultKernel(_kernel).totalAssets(_asset);
    }

    function _maxDeposit(address _kernel, address _asset) internal view returns (uint256) {
        return IRoycoVaultKernel(_kernel).maxDeposit(_asset);
    }

    function _maxWithdraw(address _kernel, address _asset) internal view returns (uint256) {
        return IRoycoVaultKernel(_kernel).maxWithdraw(_asset);
    }

    function _DEPOSIT_TYPE(address _kernel) internal pure returns (IRoycoVaultKernel.ActionType) {
        return IRoycoVaultKernel(_kernel).DEPOSIT_TYPE();
    }

    function _WITHDRAW_TYPE(address _kernel) internal pure returns (IRoycoVaultKernel.ActionType) {
        return IRoycoVaultKernel(_kernel).WITHDRAW_TYPE();
    }

    function _requestDeposit(address _kernel, address _asset, address _controller, uint256 _amount) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoVaultKernel.requestDeposit, (_asset, _controller, _amount)));
    }

    function _pendingDepositRequest(address _kernel, address _asset, address _controller) internal view returns (uint256 pendingAssets) {
        return IRoycoVaultKernel(_kernel).pendingDepositRequest(_asset, _controller);
    }

    function _claimableDepositRequest(address _kernel, address _asset, address _controller) internal view returns (uint256 claimableAssets) {
        return IRoycoVaultKernel(_kernel).claimableDepositRequest(_asset, _controller);
    }

    function _pendingRedeemRequest(address _kernel, address _asset, address _controller) internal view returns (uint256 pendingShares) {
        return IRoycoVaultKernel(_kernel).pendingRedeemRequest(_asset, _controller);
    }

    function _claimableRedeemRequest(address _kernel, address _asset, address _controller) internal view returns (uint256 claimableShares) {
        return IRoycoVaultKernel(_kernel).claimableRedeemRequest(_asset, _controller);
    }

    function _deposit(address _kernel, address _asset, address _controller, uint256 _amount) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoVaultKernel.deposit, (_asset, _controller, _amount)));
    }

    function _requestWithdraw(address _kernel, address _asset, address _controller, uint256 _amount) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoVaultKernel.requestWithdraw, (_asset, _controller, _amount)));
    }

    function _withdraw(address _kernel, address _asset, address _controller, uint256 _amount, address _receiver) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoVaultKernel.withdraw, (_asset, _controller, _amount, _receiver)));
    }

    function _cancelDepositRequest(address _kernel, address _controller) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoVaultKernel.cancelDepositRequest, (_controller)));
    }

    function _pendingCancelDepositRequest(address _kernel, address _asset, address _controller) internal view returns (bool isPending) {
        return IRoycoVaultKernel(_kernel).pendingCancelDepositRequest(_asset, _controller);
    }

    function _claimableCancelDepositRequest(address _kernel, address _asset, address _controller) internal view returns (uint256 assets) {
        return IRoycoVaultKernel(_kernel).claimableCancelDepositRequest(_asset, _controller);
    }

    function _cancelRedeemRequest(address _kernel, address _controller) internal {
        _delegateCallKernel(_kernel, abi.encodeCall(IRoycoVaultKernel.cancelRedeemRequest, (_controller)));
    }

    function _pendingCancelRedeemRequest(address _kernel, address _asset, address _controller) internal view returns (bool isPending) {
        return IRoycoVaultKernel(_kernel).pendingCancelRedeemRequest(_asset, _controller);
    }

    function _claimableCancelRedeemRequest(address _kernel, address _asset, address _controller) internal view returns (uint256 shares) {
        return IRoycoVaultKernel(_kernel).claimableCancelRedeemRequest(_asset, _controller);
    }

    function _SUPPORTS_DEPOSIT_CANCELLATION(address _kernel) internal pure returns (bool) {
        return IRoycoVaultKernel(_kernel).SUPPORTS_DEPOSIT_CANCELLATION();
    }

    function _SUPPORTS_REDEMPTION_CANCELLATION(address _kernel) internal pure returns (bool) {
        return IRoycoVaultKernel(_kernel).SUPPORTS_REDEMPTION_CANCELLATION();
    }

    function _delegateCallKernel(address _kernel, bytes memory _callData) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = _kernel.delegatecall(_callData);
        require(success, KernelCallFailed(_callData, returnData));
        return returnData;
    }
}
