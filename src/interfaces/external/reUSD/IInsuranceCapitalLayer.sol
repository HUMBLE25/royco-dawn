// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IInsuranceCapitalLayer
 * @notice Interface for the reUSD insurance capital layer
 * @dev https://etherscan.io/address/0x06d4acc104b974cd99bf22e4572f48a051e59670#code
 */
interface IInsuranceCapitalLayer {
    function convertFromShares(address token, uint256 shares) external view returns (uint256);
}
