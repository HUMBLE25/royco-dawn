// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {
    AccessControlEnumerableUpgradeable
} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { PausableUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { RoycoRoles } from "./RoycoRoles.sol";

abstract contract RoycoAuth is AccessControlEnumerableUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable {
    /// @notice Thrown when the owner is the zero address
    error INVALID_OWNER(address owner);
    /// @notice Thrown when the pauser is the zero address
    error INVALID_PAUSER(address pauser);
    /// @notice Thrown when the admin role cannot be disabled
    error ADMIN_ROLE_CANNOT_BE_DISABLED();

    /// @dev Emitted when the role gating is disabled for a role
    /// @param role The role that the gating is disabled for
    /// @param disabled True if the gating is disabled, false otherwise
    event RoleGatingDisabledSet(bytes32 role, bool disabled);

    /// @dev Emitted when the function gating is disabled for a function signature
    /// @param functionSignature The function signature that the gating is disabled for
    /// @param disabled True if the gating is disabled, false otherwise
    event FunctionGatingDisabledSet(bytes4 functionSignature, bool disabled);

    /// @custom:storage-location erc7201:Royco.storage.RoycoAuthStorage
    struct RoycoAuthStorage {
        mapping(bytes32 role => bool isRoleGatingDisabled) isRoleGatingDisabled;
        mapping(bytes4 functionSignature => bool isFunctionGatingDisabled) isFunctionGatingDisabled;
    }

    // keccak256(abi.encode(uint256(keccak256("Royco.storage.RoycoAuth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RoycoAuthStorageLocation = 0xc6351ca3982f48b7bceb4d41d4ea8768b3c95833ea37fa7955947ef4cfee2d00;

    /// @dev If role gating is enabled for the specified role, the caller must have the role
    ///      Otherwise, the caller can be any account
    modifier onlyEnabledRole(bytes32 role) {
        _onlyEnabledRole(role);
        _;
    }

    function __RoycoAuth_init(address _owner, address _pauser) internal onlyInitializing {
        require(_owner != address(0), INVALID_OWNER(_owner));
        require(_pauser != address(0), INVALID_PAUSER(_pauser));

        __AccessControlEnumerable_init();
        __AccessControl_init();
        __Ownable_init(_owner);
        __Ownable2Step_init();
        __Pausable_init();

        // Grant the initial owner the DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(RoycoRoles.PAUSER_ROLE, _pauser);
    }

    /// @dev Sets whether role gating is disabled for the specified role
    /// @param role The role to set the gating for
    /// @param disabled True if the gating should be disabled, false otherwise
    function setRoleGatingDisabled(bytes32 role, bool disabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(role != DEFAULT_ADMIN_ROLE, ADMIN_ROLE_CANNOT_BE_DISABLED());
        _getRoycoAuthStorage().isRoleGatingDisabled[role] = disabled;
        emit RoleGatingDisabledSet(role, disabled);
    }

    /// @dev Sets whether function gating is disabled for the specified function signature
    /// @param functionSignature The function signature to set the gating for
    /// @param disabled True if the gating should be disabled, false otherwise
    function setFunctionGatingDisabled(bytes4 functionSignature, bool disabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getRoycoAuthStorage().isFunctionGatingDisabled[functionSignature] = disabled;
        emit FunctionGatingDisabledSet(functionSignature, disabled);
    }

    /// @dev Pauses the contract
    function pause() external onlyRole(RoycoRoles.PAUSER_ROLE) {
        _pause();
    }

    /// @dev Unpauses the contract
    function unpause() external onlyRole(RoycoRoles.PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Returns whether role gating is disabled for the specified role
    /// @param role The role to check
    /// @return True if role gating is disabled, false otherwise
    function isRoleGatingDisabled(bytes32 role) public view returns (bool) {
        return _getRoycoAuthStorage().isRoleGatingDisabled[role];
    }

    /// @dev Returns whether function gating is disabled for the specified function signature
    /// @param functionSignature The function signature to check
    /// @return True if function gating is disabled, false otherwise
    function isFunctionGatingDisabled(bytes4 functionSignature) public view returns (bool) {
        return _getRoycoAuthStorage().isFunctionGatingDisabled[functionSignature];
    }

    /// @dev Overrides the Ownable2StepUpgradeable function to revoke the DEFAULT_ADMIN_ROLE from the previous owner and grant it to the new owner
    function _transferOwnership(address newOwner) internal virtual override {
        require(newOwner != address(0) && newOwner != owner(), INVALID_OWNER(newOwner));

        // Transfer the DEFAULT_ADMIN_ROLE from the previous owner to the new owner
        // We ignore return values to ensure the actions are idempotent
        _revokeRole(DEFAULT_ADMIN_ROLE, owner());
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);

        // Transfer the ownership to the new owner
        super._transferOwnership(newOwner);
    }

    /// @dev Checks if the caller has the specified role, taking into account role gating and function gating
    /// @param role The role to check
    /// @dev Reverts if the caller does not have the role
    function _onlyEnabledRole(bytes32 role) internal view {
        if (!isRoleGatingDisabled(role) && !isFunctionGatingDisabled(msg.sig)) {
            _checkRole(role);
        }
    }

    function _getRoycoAuthStorage() private pure returns (RoycoAuthStorage storage $) {
        assembly ("memory-safe") {
            $.slot := RoycoAuthStorageLocation
        }
    }
}
