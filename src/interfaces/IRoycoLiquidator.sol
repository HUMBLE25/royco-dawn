// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IRoycoLiquidator {
    function onRoycoLiquidation(uint256 _repaidCommitmentAmount, uint256 _seizedCollateralAmount, bytes calldata _data) external;
}
