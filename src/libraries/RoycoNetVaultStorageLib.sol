// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IRoycoOracle } from "../interfaces/IRoycoOracle.sol";
import { IRoycoVaultKernel } from "../interfaces/IRoycoVaultKernel.sol";
import { RoycoVaultKernelLib } from "./RoycoVaultKernelLib.sol";

/// @custom:storage-location erc7201:RoycoNet.storage.RoycoNetVaultState
struct RoycoNetVaultState {
    address factory;
    address kernel;
    address jtVault;
    uint8 decimalsOffset;
    address feeClaimant;
    uint24 yieldFeeBPS;
    uint24 jtTrancheCoverageFactorBPS; // The expected percentage of the senior tranche's total assets that will be insured by the junior tranche
    uint256 lastTotalAssets;
    IRoycoVaultKernel.ActionType DEPOSIT_TYPE;
    IRoycoVaultKernel.ActionType WITHDRAW_TYPE;
    bool SUPPORTS_DEPOSIT_CANCELLATION;
    bool SUPPORTS_REDEMPTION_CANCELLATION;
    mapping(address owner => mapping(address operator => bool isOperator)) isOperator;
}

library RoycoNetVaultStorageLib {
    uint256 public constant MAX_YIELD_FEE_BPS = 0.33e4;

    uint256 internal constant BPS_DENOMINATOR = 1e4;

    error MaxFeeExceeded();

    // keccak256(abi.encode(uint256(keccak256("RoycoNet.storage.RoycoNetVaultState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROYCO_NET_VAULT_STORAGE_SLOT = 0x434de18ad37bae19afbc978304ebc2e362ce3fb33d19d26c18c7d09d4f35e000;

    function _getRoycoNetVaultStorage() internal pure returns (RoycoNetVaultState storage $) {
        assembly ("memory-safe") {
            $.slot := ROYCO_NET_VAULT_STORAGE_SLOT
        }
    }

    function __RoycoNetVault_init(
        address _factory,
        address _kernel,
        address _feeClaimant,
        uint24 _yieldFeeBPS,
        address _jtVault,
        uint24 _jtTrancheCoverageFactorBPS,
        uint8 _decimalsOffset
    )
        internal
    {
        require(_yieldFeeBPS <= MAX_YIELD_FEE_BPS, MaxFeeExceeded());
        RoycoNetVaultState storage $ = _getRoycoNetVaultStorage();
        $.factory = _factory;
        $.kernel = _kernel;
        $.decimalsOffset = _decimalsOffset;
        $.feeClaimant = _feeClaimant;
        $.yieldFeeBPS = _yieldFeeBPS;
        $.jtVault = _jtVault;
        $.jtTrancheCoverageFactorBPS = _jtTrancheCoverageFactorBPS;
        $.SUPPORTS_DEPOSIT_CANCELLATION = RoycoVaultKernelLib._SUPPORTS_DEPOSIT_CANCELLATION(_kernel);
        $.SUPPORTS_REDEMPTION_CANCELLATION = RoycoVaultKernelLib._SUPPORTS_REDEMPTION_CANCELLATION(_kernel);
        $.DEPOSIT_TYPE = RoycoVaultKernelLib._DEPOSIT_TYPE(_kernel);
        $.WITHDRAW_TYPE = RoycoVaultKernelLib._WITHDRAW_TYPE(_kernel);
    }

    function _getFactory() internal view returns (address) {
        return _getRoycoNetVaultStorage().factory;
    }

    function _getKernel() internal view returns (address) {
        return _getRoycoNetVaultStorage().kernel;
    }

    function _getDecimalsOffset() internal view returns (uint8) {
        return _getRoycoNetVaultStorage().decimalsOffset;
    }

    function _getYieldFeeBPS() internal view returns (uint64) {
        return _getRoycoNetVaultStorage().yieldFeeBPS;
    }

    function _setYieldFeeBPS(uint24 _yieldFeeBPS) internal {
        require(_yieldFeeBPS <= MAX_YIELD_FEE_BPS, MaxFeeExceeded());
        _getRoycoNetVaultStorage().yieldFeeBPS = _yieldFeeBPS;
    }

    function _getLastTotalAssets() internal view returns (uint256) {
        return _getRoycoNetVaultStorage().lastTotalAssets;
    }

    function _setLastTotalAssets(uint256 _newLastTotalAssets) internal {
        _getRoycoNetVaultStorage().lastTotalAssets = _newLastTotalAssets;
    }

    function _isOperator(address _owner, address _operator) internal view returns (bool) {
        return _getRoycoNetVaultStorage().isOperator[_owner][_operator];
    }

    function _setOperator(address _owner, address _operator, bool _approved) internal {
        _getRoycoNetVaultStorage().isOperator[_owner][_operator] = _approved;
    }

    function _getDepositType() internal view returns (IRoycoVaultKernel.ActionType) {
        return _getRoycoNetVaultStorage().DEPOSIT_TYPE;
    }

    function _getWithdrawType() internal view returns (IRoycoVaultKernel.ActionType) {
        return _getRoycoNetVaultStorage().WITHDRAW_TYPE;
    }

    function _getJuniorTrancheVault() internal view returns (IERC4626) {
        return IERC4626(_getRoycoNetVaultStorage().jtVault);
    }

    function _getJuniorTrancheCoverageFactorBPS() internal view returns (uint24) {
        return _getRoycoNetVaultStorage().jtTrancheCoverageFactorBPS;
    }

    function _SUPPORTS_DEPOSIT_CANCELLATION() internal view returns (bool) {
        return _getRoycoNetVaultStorage().SUPPORTS_DEPOSIT_CANCELLATION;
    }

    function _SUPPORTS_REDEMPTION_CANCELLATION() internal view returns (bool) {
        return _getRoycoNetVaultStorage().SUPPORTS_REDEMPTION_CANCELLATION;
    }
}
