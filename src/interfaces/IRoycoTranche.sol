// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IRoycoTranche {
    /// @notice Returns the net assets controlled by the tranche in the tranche's base asset
    function getNAV() external view returns (uint256);
}
