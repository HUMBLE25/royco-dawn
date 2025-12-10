// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title RoycoRoles
 * @notice Library containing role constants for the Royco protocol access control system
 */
library RoycoRoles {
    /// Common roles
    bytes32 public constant PAUSER_ROLE = keccak256(abi.encode("ROYCO_PAUSER_ROLE"));
    bytes32 public constant UPGRADER_ROLE = keccak256(abi.encode("ROYCO_UPGRADER_ROLE"));

    /// Tranche roles
    bytes32 public constant DEPOSIT_ROLE = keccak256(abi.encode("ROYCO_DEPOSIT_ROLE"));
    bytes32 public constant REDEEM_ROLE = keccak256(abi.encode("ROYCO_REDEEM_ROLE"));
    bytes32 public constant CANCEL_DEPOSIT_ROLE = keccak256("ROYCO_CANCEL_DEPOSIT_ROLE");
    bytes32 public constant CANCEL_REDEEM_ROLE = keccak256(abi.encode("ROYCO_CANCEL_REDEEM_ROLE"));

    /// Kernel roles
    bytes32 public constant SYNC_ROLE = keccak256(abi.encode("ROYCO_SYNC_ROLE"));
}

