// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @notice Storage state for the Royco Aave V3 Kernel
 * @custom:storage-location erc7201:Royco.storage.AaveV3KernelState
 * @custom:field pool - The address of the Aave V3 pool
 * @custom:field poolAddressesProvider - The address of the Aave V3 pool addresses provider
 * @custom:field asset - The address of the tranche's base asset
 * @custom:field aToken - The address of the tranche's base asset's A Token
 */
struct AaveV3KernelState {
    address pool;
    address poolAddressesProvider;
    address asset;
    address aToken;
}

/**
 * @title AaveV3KernelStorageLib
 * @notice Library for managing Royco Aave V3 Kernel storage using the ERC7201 pattern
 * @dev Provides functions to safely access the set and get the Aave V3 kernel state
 */
library AaveV3KernelStorageLib {
    /// @dev Storage slot for AaveV3KernelState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.AaveV3KernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AAVE_V3_KERNEL_STORAGE_SLOT = 0xb4f7263fba855500e28c14eae8633159faa45c62cdc58b475aae6add84ceca00;

    /**
     * @notice Returns a storage pointer to the AaveV3KernelState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer to the Aave V3 kernel state
     */
    function _getAaveV3KernelStorage() internal pure returns (AaveV3KernelState storage $) {
        assembly ("memory-safe") {
            $.slot := AAVE_V3_KERNEL_STORAGE_SLOT
        }
    }

    /**
     * @notice Initializes the Aave V3 kernel state
     * @param _pool The address of the Aave V3 pool
     * @param _poolAddressesProvider The address of the Aave V3 pool addresses provider
     * @param _asset - The address of the tranche's base asset
     * @param _aToken - The address of the tranche's base asset's A Token
     */
    function __AaveV3Kernel_init(address _pool, address _poolAddressesProvider, address _asset, address _aToken) internal {
        // Set the initial state of the Aave V3 kernel
        AaveV3KernelState storage $ = _getAaveV3KernelStorage();
        $.pool = _pool;
        $.poolAddressesProvider = _poolAddressesProvider;
        $.asset = _asset;
        $.aToken = _aToken;
    }
}
