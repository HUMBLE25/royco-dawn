// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library ConstantsLib {
    /// @dev Constant for the WAD scaling factor
    uint256 public constant WAD = 1e18;

    /// @dev Constant for the RAY scaling factor
    uint256 public constant RAY = 1e27;

    /// @dev The minimum coverage expressed in WAD
    /// Minimum coverage = 1%
    uint256 public constant MIN_COVERAGE_WAD = 0.01e18;

    /// @dev The max protocol fee on yield
    uint256 public constant MAX_YIELD_FEE_WAD = 0.33e18;
}
