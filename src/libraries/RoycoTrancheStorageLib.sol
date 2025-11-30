// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { ExecutionModel, RoycoKernelLib } from "./RoycoKernelLib.sol";

/**
 * @notice Storage state for Royco Tranche contracts
 * @custom:storage-location erc7201:Royco.storage.RoycoTrancheState
 * @custom:field royco - The address of the Royco factory contract
 * @custom:field kernel - The address of the kernel contract handling strategy logic
 * @custom:field complementTranche - The address of the paired junior tranche
 * @custom:field coverageWAD - The percentage of tranche assets insured by junior tranche (WAD = 100%)
 * @custom:field decimalsOffset - Decimals offset for share token precision
 * @custom:field lastNAV - The last recorded NAV of the tranche
 * @custom:field DEPOSIT_EXECUTION_MODEL - The kernel execution model for deposit operations
 * @custom:field WITHDRAW_EXECUTION_MODEL - The kernel execution model for withdrawal operations
 * @custom:field isOperator - Nested mapping tracking operator approvals for owners
 */
struct RoycoTrancheState {
    address royco;
    address kernel;
    address complementTranche;
    uint64 coverageWAD;
    uint8 decimalsOffset;
    uint256 lastNAV;
    ExecutionModel DEPOSIT_EXECUTION_MODEL;
    ExecutionModel WITHDRAW_EXECUTION_MODEL;
    mapping(address owner => mapping(address operator => bool isOperator)) isOperator;
}

/**
 * @title RoycoTrancheStorageLib
 * @notice Library for managing Royco Tranche storage using ERC-7201 pattern
 * @dev Provides functions to safely access and modify tranche state
 */
library RoycoTrancheStorageLib {
    /// @dev Storage slot for RoycoTrancheState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.RoycoTrancheState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROYCO_TRANCHE_STORAGE_SLOT = 0x25265df6fdb5acadb02f38e62cea4bba666d308120ed42c208a4ef005c50ec00;

    /**
     * @notice Returns a reference to the RoycoTrancheState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage reference to the tranche state
     */
    function _getRoycoTrancheStorage() internal pure returns (RoycoTrancheState storage $) {
        assembly ("memory-safe") {
            $.slot := ROYCO_TRANCHE_STORAGE_SLOT
        }
    }

    /**
     * @notice Initializes the tranche storage state
     * @dev Sets up all initial parameters and validates fee constraints
     * @param _royco The address of the Royco factory contract
     * @param _kernel The address of the kernel contract handling strategy logic
     * @param _coverageWAD The percentage of tranche assets insured by junior tranche (WAD = 100%)
     * @param _complementTranche The address of the paired junior tranche vault
     * @param _decimalsOffset Decimals offset for share token precision
     */
    function __RoycoTranche_init(address _royco, address _kernel, uint64 _coverageWAD, address _complementTranche, uint8 _decimalsOffset) internal {
        // Set the initial state of the tranche
        RoycoTrancheState storage $ = _getRoycoTrancheStorage();
        $.royco = _royco;
        $.kernel = _kernel;
        $.complementTranche = _complementTranche;
        $.coverageWAD = _coverageWAD;
        $.decimalsOffset = _decimalsOffset;
        $.DEPOSIT_EXECUTION_MODEL = RoycoKernelLib._DEPOSIT_EXECUTION_MODEL(_kernel);
        $.WITHDRAW_EXECUTION_MODEL = RoycoKernelLib._WITHDRAW_EXECUTION_MODEL(_kernel);
    }

    /**
     * @notice Returns the address of the Royco factory contract
     * @return The factory contract address
     */
    function _getRoyco() internal view returns (address) {
        return _getRoycoTrancheStorage().royco;
    }

    /**
     * @notice Returns the address of the kernel contract
     * @return The kernel contract address handling strategy logic
     */
    function _getKernel() internal view returns (address) {
        return _getRoycoTrancheStorage().kernel;
    }

    /**
     * @notice Returns the junior complement tranche (junior if senior, if junior)
     * @return The complement tranche
     */
    function _getComplementTranche() internal view returns (address) {
        return _getRoycoTrancheStorage().complementTranche;
    }

    /**
     * @notice Returns the coverage percentage
     * @return The percentage of tranche assets insured by junior tranche (WAD = 100%)
     */
    function _getCoverageRatioWAD() internal view returns (uint64) {
        return _getRoycoTrancheStorage().coverageWAD;
    }

    /**
     * @notice Returns the last recorded NAV for this tranche
     * @return The last recorded NAV for this tranche in its base asset
     */
    function _getLastNAV() internal view returns (uint256) {
        return _getRoycoTrancheStorage().lastNAV;
    }

    /**
     * @notice Checks if an operator is approved for a given owner
     * @param _owner The owner address
     * @param _operator The operator address to check
     * @return True if the operator is approved, false otherwise
     */
    function _isOperator(address _owner, address _operator) internal view returns (bool) {
        return _getRoycoTrancheStorage().isOperator[_owner][_operator];
    }

    /**
     * @notice Sets operator approval for an owner
     * @param _owner The owner address
     * @param _operator The operator address
     * @param _approved Whether the operator is approved
     */
    function _setOperator(address _owner, address _operator, bool _approved) internal {
        _getRoycoTrancheStorage().isOperator[_owner][_operator] = _approved;
    }

    /**
     * @notice Returns the kernel execution model for deposit operations
     * @return The deposit execution model from the kernel
     */
    function _getDepositExecutionModel() internal view returns (ExecutionModel) {
        return _getRoycoTrancheStorage().DEPOSIT_EXECUTION_MODEL;
    }

    /**
     * @notice Returns the kernel execution model for withdrawal operations
     * @return The withdrawal execution model from the kernel
     */
    function _getWithdrawalExecutionModel() internal view returns (ExecutionModel) {
        return _getRoycoTrancheStorage().WITHDRAW_EXECUTION_MODEL;
    }

    /**
     * @notice Returns the decimals offset for share token precision
     * @return The decimals offset value
     */
    function _getDecimalsOffset() internal view returns (uint8) {
        return _getRoycoTrancheStorage().decimalsOffset;
    }
}
