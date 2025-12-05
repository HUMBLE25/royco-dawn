// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { ExecutionModel, IRoycoBaseKernel } from "../interfaces/kernel/IRoycoBaseKernel.sol";

/**
 * @notice Storage state for Royco Tranche contracts
 * @custom:storage-location erc7201:Royco.storage.RoycoTrancheState
 * @custom:field royco - The address of the Royco factory contract
 * @custom:field kernel - The address of the kernel contract handling strategy logic
 * @custom:field marketId - The identifier of the Royco market this tranche is linked to
 * @custom:field complementTranche - The address of the paired junior tranche
 * @custom:field coverageWAD - The percentage of tranche assets insured by junior tranche (WAD = 100%)
 * @custom:field decimalsOffset - Decimals offset for share token precision
 * @custom:field lastRawNAV - The last recorded NAV of the tranche
 * @custom:field DEPOSIT_EXECUTION_MODEL - The kernel execution model for deposit operations
 * @custom:field WITHDRAW_EXECUTION_MODEL - The kernel execution model for withdrawal operations
 * @custom:field isOperator - Nested mapping tracking operator approvals for owners
 */
struct RoycoTrancheState {
    address royco;
    address kernel;
    bytes32 marketId;
    address complementTranche;
    uint64 coverageWAD;
    uint8 decimalsOffset;
    uint256 lastRawNAV;
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
     * @param _marketId The identifier of the Royco market this tranche is linked to
     * @param _complementTranche The address of the paired junior tranche vault
     * @param _decimalsOffset Decimals offset for share token precision
     */
    function __RoycoTranche_init(address _royco, address _kernel, bytes32 _marketId, address _complementTranche, uint8 _decimalsOffset) internal {
        // Set the initial state of the tranche
        RoycoTrancheState storage $ = _getRoycoTrancheStorage();
        $.royco = _royco;
        $.kernel = _kernel;
        $.marketId = _marketId;
        $.complementTranche = _complementTranche;
        $.decimalsOffset = _decimalsOffset;
        $.DEPOSIT_EXECUTION_MODEL = IRoycoBaseKernel(_kernel).getDepositExecutionModel();
        $.WITHDRAW_EXECUTION_MODEL = IRoycoBaseKernel(_kernel).getWithdrawExecutionModel();
    }
}
