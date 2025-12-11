// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Initialization parameters for the Royco Base Kernel
/// @custom:field seniorTranche - The address of the Royco senior tranche associated with this kernel
/// @custom:field juniorTranche - The address of the Royco junior tranche associated with this kernel
/// @custom:field coverageWAD - The coverage ratio that the senior tranche is expected to be protected by scaled by WAD
/// @custom:field betaWAD - The junior tranche's sensitivity to the same downside stress that affects the senior tranche
///                For example, beta is 0 when JT is in the RFR and 1 when JT is in the same opportunity as senior
/// @custom:field rdm - The market's Reward Distribution Model (RDM), responsible for determining the ST's yield split between ST and JT
struct BaseKernelInitParams {
    address seniorTranche;
    address juniorTranche;
    uint64 coverageWAD;
    uint96 betaWAD;
    address rdm;
}

/// @notice Storage state for the Royco Base Kernel
/// @custom:storage-location erc7201:Royco.storage.BaseKernelState
/// @custom:field seniorTranche - The address of the Royco senior tranche associated with this kernel
/// @custom:field coverageWAD - The coverage ratio that the senior tranche is expected to be protected by scaled by WAD
/// @custom:field juniorTranche - The address of the Royco junior tranche associated with this kernel
/// @custom:field betaWAD - The JT's sensitivity to the same downside stress that affects ST scaled by WAD
///                         For example, beta is 0 when JT is in the RFR and 1 when JT is in the same opportunity as senior
/// @custom:field rdm - The market's Reward Distribution Model (RDM), responsible for determining the ST's yield split between ST and JT
/// @custom:field lastSTRawNAV - The last recorded raw NAV (excluding any losses, coverage, and yield accrual) of the senior tranche
/// @custom:field lastJTRawNAV - The last recorded raw NAV (excluding any losses, coverage, and yield accrual) of the junior tranche
/// @custom:field lastSTEffectiveNAV - The last recorded effective NAV (including any prior applied coverage, ST yield distributions, and uncovered losses) of the senior tranche
/// @custom:field lastJTEffectiveNAV - The last recorded effective NAV (including any prior provided coverage, JT yield, ST yield distribution, and JT losses) of the junior tranche
/// @custom:field lastJTCoverageDebt - The losses that ST incurred after exhausting the JT loss-absorption buffer: represents the first claim on capital the senior tranche has on future recoveries
/// @custom:field lastSTCoverageDebt - The coverage that has been applied to ST from the JT loss-absorption buffer : represents the second claim on capital the junior tranche has on future recoveries
/// @custom:field twJTYieldShareAccruedWAD - The time-weighted junior tranche yield share (RDM output) since the last yield distribution
/// @custom:field lastAccrualTimestamp - The last time the time-weighted JT yield share accumulator was updated
/// @custom:field lastDistributionTimestamp - The last time a yield distribution occurred
struct BaseKernelState {
    address seniorTranche;
    uint64 coverageWAD;
    address juniorTranche;
    uint96 betaWAD;
    address rdm;
    uint256 lastSTRawNAV;
    uint256 lastJTRawNAV;
    uint256 lastSTEffectiveNAV;
    uint256 lastJTEffectiveNAV;
    uint256 lastJTCoverageDebt;
    uint256 lastSTCoverageDebt;
    uint192 twJTYieldShareAccruedWAD;
    uint32 lastAccrualTimestamp;
    uint32 lastDistributionTimestamp;
}

/// @title BaseKernelStorageLib
/// @notice Library for managing Royco Base Kernel storage using the ERC7201 pattern
/// @dev Provides functions to safely access the set and get the base kernel state
library BaseKernelStorageLib {
    /// @dev Storage slot for BaseKernelState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.BaseKernelState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_KERNEL_STORAGE_SLOT = 0x0e1123d8194dcf603de811512b2b6334f106b53313663d6b2df1a2b814038e00;

    /// @notice Returns a storage pointer to the BaseKernelState storage
    /// @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
    /// @return $ Storage pointer to the base kernel state
    function _getBaseKernelStorage() internal pure returns (BaseKernelState storage $) {
        assembly ("memory-safe") {
            $.slot := BASE_KERNEL_STORAGE_SLOT
        }
    }

    /// @notice Initializes the base kernel state
    /// @param _params The initialization parameters for the base kernel
    function __BaseKernel_init(BaseKernelInitParams memory _params) internal {
        // Set the initial state of the base kernel
        BaseKernelState storage $ = _getBaseKernelStorage();
        $.seniorTranche = _params.seniorTranche;
        $.coverageWAD = _params.coverageWAD;
        $.juniorTranche = _params.juniorTranche;
        $.betaWAD = _params.betaWAD;
        $.rdm = _params.rdm;
    }
}
