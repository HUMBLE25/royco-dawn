// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoRoles } from "../src/auth/RoycoRoles.sol";

/**
 * @title RolesConfiguration
 * @author Ankur Dubey, Shivaansh Kapoor
 * @notice Abstract contract containing role configuration for the Royco protocol access control system
 * @dev This contract defines the role hierarchy, admin roles, guardian roles, and execution delays
 *      for each role in the system.
 */
abstract contract RolesConfiguration is RoycoRoles {
    /// @notice Error when an unknown role is requested
    error UnknownRole(uint64 role);

    /// @notice Configuration for a single role
    struct RoleConfig {
        uint64 adminRole; // The role that can grant/revoke this role (0 for ADMIN_ROLE)
        uint64 guardianRole; // The role that can cancel operations for this role
        uint32 executionDelay; // Delay in seconds before role operations take effect
    }

    /// @notice Default admin role (OpenZeppelin AccessManager uses 0 for admin)
    uint64 public constant ADMIN_ROLE = 0;

    /**
     * @notice Returns the configuration for a given role
     * @param role The role to get configuration for
     * @return config The role configuration
     */
    function getRoleConfig(uint64 role) public pure returns (RoleConfig memory config) {
        if (role == ADMIN_PAUSER_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 0 // Pausing should be immediate
            });
        } else if (role == ADMIN_UPGRADER_ROLE) {
            return RoleConfig({ adminRole: ADMIN_ROLE, guardianRole: ROLE_GUARDIAN_ROLE, executionDelay: 1 days });
        } else if (role == LP_ROLE) {
            return RoleConfig({
                adminRole: LP_ROLE_ADMIN_ROLE, // LP admin can manage LP roles
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 0 // LP operations should be immediate
            });
        } else if (role == LP_ROLE_ADMIN_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 0 // LP admin operations should be immediate
            });
        } else if (role == SYNC_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 0 // Sync operations should be immediate
            });
        } else if (role == ADMIN_KERNEL_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 1 days // Kernel admin operations require delay
            });
        } else if (role == ADMIN_ACCOUNTANT_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 1 days // Accountant admin operations require delay
            });
        } else if (role == ADMIN_PROTOCOL_FEE_SETTER_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 1 days // Fee changes require delay
            });
        } else if (role == ADMIN_ORACLE_QUOTER_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ROLE_GUARDIAN_ROLE,
                executionDelay: 0 // Oracle updates should be immediate
            });
        } else if (role == ROLE_GUARDIAN_ROLE) {
            return RoleConfig({
                adminRole: ADMIN_ROLE,
                guardianRole: ADMIN_ROLE, // Only admin can cancel guardian operations
                executionDelay: 0 // Guardian operations should be immediate
            });
        } else {
            revert UnknownRole(role);
        }
    }
}
