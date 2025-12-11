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
    /// @notice Thrown when the calldata hash is invalid
    error INVALID_CALLDATA_HASH(bytes32 expectedHash, bytes32 actualHash);
    /// @notice Thrown when the operation is not scheduled
    error OPERATION_NOT_READY(uint256 currentTimestamp, uint256 scheduledTimestamp);
    /// @notice Thrown when the execution delay length mismatch
    error INVALID_EXECUTION_DELAY_LENGTH_MISMATCH(uint256 expectedLength, uint256 actualLength);
    /// @notice Thrown when the operation is not scheduled
    error OPERATION_NOT_SCHEDULED(bytes4 selector);

    /// @notice Struct to store the scheduled operation
    /// @custom:field calldataHash The calldata hash of the operation
    /// @custom:field executeAt The timestamp at which the operation can be executed
    struct ScheduledOperation {
        bytes32 calldataHash;
        uint256 executeAt;
    }

    /// @notice Emitted when an operation is scheduled
    /// @param selector The function selector of the operation
    /// @param calldataHash The hash of the operation's calldata
    /// @param scheduler The address that scheduled the operation
    /// @param executeAt The timestamp when the operation can be executed
    event OperationScheduled(bytes4 indexed selector, bytes32 indexed calldataHash, address indexed scheduler, uint256 executeAt);

    /// @notice Emitted when the execution delay is updated for a function
    /// @param selector The function selector
    /// @param delay The new execution delay in seconds
    event ExecutionDelayUpdated(bytes4 indexed selector, uint256 delay);

    /// @notice Emitted when an operation is canceled
    /// @param selector The function selector of the canceled operation
    /// @param canceler The address that canceled the operation
    event OperationCanceled(bytes4 indexed selector, address indexed canceler);

    /// @notice Emitted when the execution delay is updated for multiple functions
    /// @param selectors Array of function selectors
    /// @param delays Array of new execution delays in seconds
    event ExecutionDelayUpdated(bytes4[] indexed selectors, uint256[] indexed delays);

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
        /// @notice Mapping of roles to their gating disabled status
        mapping(bytes32 role => bool isRoleGatingDisabled) isRoleGatingDisabled;

        /// @notice Mapping of function signatures to their gating disabled status
        mapping(bytes4 selector => bool isFunctionGatingDisabled) isFunctionGatingDisabled;

        /// @notice Mapping of function selectors to their execution delays in seconds
        mapping(bytes4 selector => uint256 delay) executionDelay;

        /// @notice Mapping of function selectors to their scheduled operations
        mapping(bytes4 selector => ScheduledOperation operation) scheduledOperations;
    }

    // keccak256(abi.encode(uint256(keccak256("Royco.storage.RoycoAuth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RoycoAuthStorageLocation = 0xc6351ca3982f48b7bceb4d41d4ea8768b3c95833ea37fa7955947ef4cfee2d00;

    modifier checkRoleAndDelayIfGated(bytes32 role) {
        if (!_checkRoleAndDelayIfGated(role)) {
            return;
        }
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
    function setRoleGatingDisabled(bytes32 role, bool disabled) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(role != DEFAULT_ADMIN_ROLE, ADMIN_ROLE_CANNOT_BE_DISABLED());
        _getRoycoAuthStorage().isRoleGatingDisabled[role] = disabled;
        emit RoleGatingDisabledSet(role, disabled);
    }

    /// @dev Sets whether function gating is disabled for the specified function signature
    /// @param functionSignature The function signature to set the gating for
    /// @param disabled True if the gating should be disabled, false otherwise
    function setFunctionGatingDisabled(bytes4 functionSignature, bool disabled) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _getRoycoAuthStorage().isFunctionGatingDisabled[functionSignature] = disabled;
        emit FunctionGatingDisabledSet(functionSignature, disabled);
    }

    /// @notice Sets the execution delay for a function
    /// @param selectors The selectors of the functions to update the delay for
    /// @param delays The new delays for the functions
    function setExecutionDelay(bytes4[] calldata selectors, uint256[] calldata delays) external virtual onlyRole(RoycoRoles.SCHEDULER_MANAGER_ROLE) {
        RoycoAuthStorage storage $ = _getRoycoAuthStorage();
        require(selectors.length == delays.length, INVALID_EXECUTION_DELAY_LENGTH_MISMATCH(selectors.length, delays.length));
        for (uint256 i = 0; i < selectors.length; i++) {
            $.executionDelay[selectors[i]] = delays[i];
            emit ExecutionDelayUpdated(selectors[i], delays[i]);
        }
    }

    /// @notice Cancels a scheduled operation
    /// @param selector The selector of the operation to cancel
    function cancelScheduledOperation(bytes4 selector) external virtual onlyRole(RoycoRoles.SCHEDULER_MANAGER_ROLE) {
        RoycoAuthStorage storage $ = _getRoycoAuthStorage();
        ScheduledOperation storage operation = $.scheduledOperations[selector];
        require(operation.executeAt > 0, OPERATION_NOT_SCHEDULED(selector));
        delete $.scheduledOperations[selector];
        emit OperationCanceled(selector, msg.sender);
    }

    /// @dev Pauses the contract
    function pause() external virtual onlyRole(RoycoRoles.PAUSER_ROLE) {
        _pause();
    }

    /// @dev Unpauses the contract
    function unpause() external virtual onlyRole(RoycoRoles.PAUSER_ROLE) {
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

    /// @dev Returns the execution delay for the specified function selector
    /// @param selector The function selector to check
    /// @return The execution delay in seconds
    function getExecutionDelay(bytes4 selector) public view returns (uint256) {
        return _getRoycoAuthStorage().executionDelay[selector];
    }

    /// @dev Returns the scheduled operation for the specified function selector
    /// @param selector The function selector to check
    /// @return The scheduled operation
    function getScheduledOperation(bytes4 selector) public view returns (ScheduledOperation memory) {
        return _getRoycoAuthStorage().scheduledOperations[selector];
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

    /// @dev Checks if the caller has the specified role and if the function has a delay set
    /// @dev If delay is set, schedules the operation if it is not already scheduled and returns the allowExecution and wasPending flags
    /// @param role The role to check
    /// @return allowExecution True if the caller has the role and the function has a delay set, false otherwise
    function _checkRoleAndDelayIfGated(bytes32 role) private returns (bool allowExecution) {
        // If role gating or function gating is disabled, return
        if (isRoleGatingDisabled(role) || isFunctionGatingDisabled(msg.sig)) {
            return true;
        }

        // Check whether the caller has the required role
        _checkRole(role);

        RoycoAuthStorage storage $ = _getRoycoAuthStorage();

        // Check if the function has a delay set
        uint256 delay = $.executionDelay[msg.sig];
        // If the function has no delay set, return
        if (delay == 0) {
            return true;
        }

        // Read any scheduled operation for the function from storage
        ScheduledOperation storage operation = $.scheduledOperations[msg.sig];
        bytes32 calldataHash = keccak256(msg.data);

        if (operation.executeAt == 0) {
            // If the operation has not been scheduled, schedule it with the delay set for the function
            uint256 executeAt = block.timestamp + delay;
            operation.executeAt = executeAt;
            operation.calldataHash = calldataHash;
            emit OperationScheduled(msg.sig, calldataHash, msg.sender, executeAt);
            // Return false to prevent the operation from being executed immediately
            return false;
        } else {
            // If the operation has been scheduled, execute it if the calldata hash is the same and the operation is ready
            require(block.timestamp >= operation.executeAt, OPERATION_NOT_READY(block.timestamp, operation.executeAt));
            require(operation.calldataHash == calldataHash, INVALID_CALLDATA_HASH(operation.calldataHash, calldataHash));
            // Delete the scheduled operation from storage
            delete $.scheduledOperations[msg.sig];
            // Return true to allow the operation to be executed
            return true;
        }
    }

    function _getRoycoAuthStorage() private pure returns (RoycoAuthStorage storage $) {
        assembly ("memory-safe") {
            $.slot := RoycoAuthStorageLocation
        }
    }
}
