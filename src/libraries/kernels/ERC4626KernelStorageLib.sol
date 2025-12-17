// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Storage state for the Royco ERC4626 Senior Tranche Kernel
/// @custom:storage-location erc7201:Royco.storage.ERC4626KernelState
/// @custom:field vault - The address of the ERC4626 vault
/// forge-lint: disable-next-item(pascal-case-struct)
struct ERC4626KernelState {
    address vault;
    uint256 stOwnedShares;
    uint256 jtOwnedShares;
}

/// @title ERC4626KernelStorageLib
/// @author Royco Protocol
/// @notice Library for managing Royco ERC4626 Senior Tranche Kernel storage using the ERC7201 pattern
/// @dev Provides functions to safely access the set and get the ERC4626 ST kernel state
library ERC4626KernelStorageLib {
    /// @dev Storage slot for ERC4626KernelState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.ERC4626KernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC4626_KERNEL_STORAGE_SLOT = 0x46aebd32ce37edb869d974fc16e055976a60eee64611d85a743ba2c5e1523200;

    /// @notice Returns a storage pointer to the ERC4626KernelState storage
    /// @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
    /// @return $ Storage pointer to the ERC4626 ST kernel state
    function _getERC4626KernelStorage() internal pure returns (ERC4626KernelState storage $) {
        assembly ("memory-safe") {
            $.slot := ERC4626_KERNEL_STORAGE_SLOT
        }
    }

    /// @notice Initializes the ERC4626 kernel state
    /// @param _vault The address of the ERC4626 vault
    function __ERC4626Kernel_init(address _vault) internal {
        ERC4626KernelState storage $ = _getERC4626KernelStorage();
        $.vault = _vault;
    }
}
