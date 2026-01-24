// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title RoycoRoles
 * @author Ankur Dubey, Shivaansh Kapoor
 * @notice Abstract contract containing role constants for the Royco protocol access control system
 */
abstract contract RoycoRoles {
    /// Common roles
    uint64 public constant ADMIN_PAUSER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_PAUSER_ROLE"))));
    uint64 public constant ADMIN_UPGRADER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_UPGRADER_ROLE"))));

    /// Tranche roles
    uint64 public constant LP_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_LP_ROLE"))));

    /// Kernel roles
    uint64 public constant SYNC_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_SYNC_ROLE"))));
    uint64 public constant ADMIN_KERNEL_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_KERNEL_ROLE"))));

    /// Accountant roles
    uint64 public constant ADMIN_ACCOUNTANT_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_ACCOUNTANT_ROLE"))));
    uint64 public constant ADMIN_PROTOCOL_FEE_SETTER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_PROTOCOL_FEE_SETTER_ROLE"))));

    /// Quoter roles
    uint64 public constant ADMIN_ORACLE_QUOTER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_ORACLE_QUOTER_ROLE"))));

    /// Meta Roles
    uint64 public constant LP_ROLE_ADMIN_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_LP_ROLE_ADMIN_ROLE"))));

    /// Guardian role - can cancel delayed operations for all roles
    uint64 public constant ROLE_GUARDIAN_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ROLE_GUARDIAN_ROLE"))));
}
