// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @notice Storage state for the Royco ERC4626 Senior Tranche Kernel
 * @custom:storage-location erc7201:Royco.storage.ERC4626STKernelState
 * @custom:field vault - The address of the ERC4626 vault
 * @custom:field asset - The address of the senior tranche's base asset
 */
struct ERC4626STKernelState {
    address vault;
    address asset;
}

/**
 * @title ERC4626STKernelStorageLib
 * @author Royco Protocol
 * @notice Library for managing Royco ERC4626 Senior Tranche Kernel storage using the ERC7201 pattern
 * @dev Provides functions to safely access the set and get the ERC4626 ST kernel state
 */
library ERC4626STKernelStorageLib {
    /// @dev Storage slot for ERC4626STKernelState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.ERC4626STKernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC4626_ST_KERNEL_STORAGE_SLOT = 0xf93caea3064cbce48e1771cf1c578d0020880f43130f18cb858fea5e040d7100;

    /**
     * @notice Returns a storage pointer to the ERC4626STKernelState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer to the ERC4626 ST kernel state
     */
    function _getERC4626STKernelStorage() internal pure returns (ERC4626STKernelState storage $) {
        assembly ("memory-safe") {
            $.slot := ERC4626_ST_KERNEL_STORAGE_SLOT
        }
    }

    /**
     * @notice Initializes the ERC4626 ST kernel state
     * @param _vault The address of the ERC4626 vault
     * @param _asset The address of the senior tranche's base asset
     */
    function __ERC4626STKernel_init(address _vault, address _asset) internal {
        ERC4626STKernelState storage $ = _getERC4626STKernelStorage();
        $.vault = _vault;
        $.asset = _asset;
    }
}