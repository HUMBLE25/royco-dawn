// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Interface for the Neutrl Router
/// @dev Based on https://etherscan.io/address/0xa052883ebEe7354FC2Aa0f9c727E657FdeCa744a#code
interface IRouter {
    function quoteRedemption(address collateralAsset, uint256 nusdAmount) external view returns (uint256);
}
