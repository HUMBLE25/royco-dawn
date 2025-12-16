// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @notice Storage state for the Royco ERC7540 Kernel
 * @custom:storage-location erc7201:Royco.storage.ERC7540KernelState
 * @custom:field vault - The address of the ERC7540 vault
 * @custom:field asset - The address of the tranche's base asset
 * forge-lint: disable-next-item(pascal-case-struct)
 */
struct ERC7540KernelState {
    address vault;
    address asset;
}

/**
 * @title ERC7540KernelStorageLib
 * @author Royco Protocol
 * @notice Library for managing Royco ERC7540 Kernel storage using the ERC7201 pattern
 * @dev Provides functions to safely access the set and get the ERC7540 kernel state
 */
library ERC7540KernelStorageLib {
    /**
     * @dev Storage slot for ERC7540KernelState using ERC-7201 pattern
     */
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.ERC7540KernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC7540_KERNEL_STORAGE_SLOT = 0xf6ffdef339f66397e33108678ec67b03203354b5f8acd2b5f86364018df63000;

    /**
     * @notice Returns a storage pointer to the ERC7540KernelState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer to the ERC7540 kernel state
     */
    function _getERC7540KernelStorage() internal pure returns (ERC7540KernelState storage $) {
        assembly ("memory-safe") {
            $.slot := ERC7540_KERNEL_STORAGE_SLOT
        }
    }

    /**
     * @notice Initializes the ERC7540 kernel state
     * @param _vault The address of the ERC7540 vault
     * @param _asset The address of the tranche's base asset
     */
    function __ERC7540Kernel_init(address _vault, address _asset) internal {
        // Set the initial state of the ERC7540 kernel
        ERC7540KernelState storage $ = _getERC7540KernelStorage();
        $.vault = _vault;
        $.asset = _asset;
    }
}
