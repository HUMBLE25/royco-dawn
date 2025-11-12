// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library ConstantsLib {
    /// @dev Constant for the WAD scaling factor
    uint256 constant WAD = 1e18;

    /// @dev Constant for the RAY scaling factor
    uint256 constant RAY = 1e27;

    /**
     * @dev Constant for the target utilization of the junior tranche (90%)
     * @dev Utilization = (senior tranche principal * expected loss percentage) / junior tranche commitments
     * @dev Invariant: junior tranche commitments >= (senior tranche principal * expected loss percentage)
     * @dev The above ensures Utilization ∈ [0,1]
     */
    uint256 constant TARGET_UTILIZATION = 0.9e18;
}
