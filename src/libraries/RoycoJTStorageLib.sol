// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { ExecutionModel, RoycoKernelLib } from "./RoycoKernelLib.sol";

/**
 * @notice Storage state for Royco Junior Tranche contracts
 * @custom:storage-location erc7201:Royco.storage.RoycoJTState
 * @custom:field royco - The address of the Royco factory contract
 * @custom:field kernel - The address of the kernel contract handling strategy logic
 * @custom:field juniorTranche - The address of the paired junior tranche
 * @custom:field rewardFeeWAD - The percentage of yield paid to protocol (WAD = 100%)
 * @custom:field feeClaimant - The address authorized to claim protocol fees
 * @custom:field coverageWAD - The percentage of senior tranche assets insured by junior tranche (WAD = 100%)
 * @custom:field decimalsOffset - Decimals offset for share token precision
 */
struct RoycoJTState {
    address royco;
    address kernel;
    address juniorTranche;
    uint64 rewardFeeWAD;
    address feeClaimant;
    uint64 coverageWAD;
    uint8 decimalsOffset;
}

/**
 * @title RoycoJTStorageLib
 * @notice Library for managing Royco Junior Tranche storage using ERC-7201 pattern
 * @dev Provides functions to safely access and modify senior tranche state
 */
library RoycoJTStorageLib {
    /// @notice Maximum allowed yield fee (33% in WAD format)
    uint256 public constant MAX_YIELD_FEE_WAD = 0.33e18;

    /// @notice Thrown when attempting to set a fee above the maximum allowed
    error MAX_FEE_EXCEEDED();

    /// @dev Storage slot for RoycoJTState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.RoycoJTState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROYCO_JT_STORAGE_SLOT = 0x83ac9927f242c6455f19a0a429298eabb548af2af634e553d66af733c1d3ef00;

    /**
     * @notice Returns a reference to the RoycoJTState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage reference to the senior tranche state
     */
    function _getRoycoJTStorage() internal pure returns (RoycoJTState storage $) {
        assembly ("memory-safe") {
            $.slot := ROYCO_JT_STORAGE_SLOT
        }
    }

    /**
     * @notice Initializes the senior tranche storage state
     * @dev Sets up all initial parameters and validates fee constraints
     * @param _royco The address of the Royco factory contract
     * @param _kernel The address of the kernel contract handling strategy logic
     * @param _rewardFeeWAD The percentage of yield paid to protocol (WAD = 100%)
     * @param _feeClaimant The address authorized to claim protocol fees
     * @param _coverageWAD The percentage of senior tranche assets insured by junior tranche (WAD = 100%)
     * @param _seniorTranche The address of the paired senior tranche vault
     * @param _decimalsOffset Decimals offset for share token precision
     */
    function __RoycoJT_init(
        address _royco,
        address _kernel,
        uint64 _rewardFeeWAD,
        address _feeClaimant,
        uint64 _coverageWAD,
        address _seniorTranche,
        uint8 _decimalsOffset
    )
        internal
    {
        // Check the protocol fee isn't greater than the max
        require(_rewardFeeWAD <= MAX_YIELD_FEE_WAD, MAX_FEE_EXCEEDED());

        // Set the initial state of the tranche
        RoycoJTState storage $ = _getRoycoJTStorage();
        $.royco = _royco;
        $.kernel = _kernel;
        $.juniorTranche = _seniorTranche;
        $.feeClaimant = _feeClaimant;
        $.rewardFeeWAD = _rewardFeeWAD;
        $.coverageWAD = _coverageWAD;
        $.decimalsOffset = _decimalsOffset;
    }

    /**
     * @notice Returns the address of the Royco factory contract
     * @return The factory contract address
     */
    function _getFactory() internal view returns (address) {
        return _getRoycoJTStorage().royco;
    }

    /**
     * @notice Returns the address of the kernel contract
     * @return The kernel contract address handling strategy logic
     */
    function _getKernel() internal view returns (address) {
        return _getRoycoJTStorage().kernel;
    }

    /**
     * @notice Returns the decimals offset for share token precision
     * @return The decimals offset value
     */
    function _getDecimalsOffset() internal view returns (uint8) {
        return _getRoycoJTStorage().decimalsOffset;
    }

    /**
     * @notice Returns the current reward fee percentage
     * @return The reward fee in WAD format (WAD = 100%)
     */
    function _getRewardFeeWAD() internal view returns (uint64) {
        return _getRoycoJTStorage().rewardFeeWAD;
    }

    /**
     * @notice Sets the yield fee percentage
     * @dev Validates that the fee does not exceed the maximum allowed
     * @param _rewardFeeWAD The new reward fee in WAD format (WAD = 100%)
     */
    function _setYieldFeeBPS(uint24 _rewardFeeWAD) internal {
        require(_rewardFeeWAD <= MAX_YIELD_FEE_WAD, MAX_FEE_EXCEEDED());
        _getRoycoJTStorage().rewardFeeWAD = _rewardFeeWAD;
    }

    /**
     * @notice Returns the junior tranche vault as an ERC4626 interface
     * @return The junior tranche vault contract
     */
    function _getSeniorTranche() internal view returns (IERC4626) {
        return IERC4626(_getRoycoJTStorage().juniorTranche);
    }
}
