// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultKernel } from "../../interfaces/IRoycoVaultKernel.sol";

/**
 * @title BaseKernel
 * @notice Base abstract contract for kernel implementations that provides delegate call protection
 * @dev Provides the foundational functionality for kernel contracts including delegatecall enforcement
 * @dev All kernel contracts should inherit from this base contract to ensure proper execution context
 *      and use the modifier as stipulated by the IRoycoVaultKernel interface.
 */
abstract contract BaseKernel is IRoycoVaultKernel {
    /// @notice Thrown when a function is called directly instead of via delegate call
    error OnlyDelegateCall();
    /// @notice Thrown when a function is not implemented or disabled
    error UnsupportedOperation();

    /// @notice The address of the kernel implementation contract
    address private immutable KERNEL_IMPLEMENTATION;

    /**
     * @notice Initializes the kernel implementation address
     * @dev Sets the implementation address to prevent direct calls to the implementation contract
     */
    constructor() {
        KERNEL_IMPLEMENTATION = address(this);
    }

    /**
     * @notice Ensures the function is called via delegatecall only
     * @dev Prevents direct calls to the kernel implementation contract
     * @dev Reverts if called directly on the implementation contract
     */
    modifier onlyDelegateCall() {
        require(address(this) != KERNEL_IMPLEMENTATION, OnlyDelegateCall());

        _;
    }

    /**
     * @notice Ensures the function reverts on being called
     */
    modifier disabled() {
        revert UnsupportedOperation();
        _;
    }
}
