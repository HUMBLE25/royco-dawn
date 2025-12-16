// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IRoycoAuth
 * @notice Interface for the RoycoAuth contract that provides access control and pausability functionality
 */
interface IRoycoAuth {
    /**
     * @notice Pauses the contract
     */
    function pause() external;

    /**
     * @notice Unpauses the contract
     */
    function unpause() external;
}
