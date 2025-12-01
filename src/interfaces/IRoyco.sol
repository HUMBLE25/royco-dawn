// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IRoyco
 * @notice Interface for Royco
 */
interface IRoyco {
    function previewSyncTrancheNAVs(bytes32 _marketId)
        external
        view
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);

    function syncTrancheNAVs(
        bytes32 _marketId,
        int256 _rawNAVDelta
    )
        external
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);
}
