// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IRDM - Reward Distribution Model Interface
 * @notice Interface for reward distribution models that determine how rewards are allocated between senior and junior tranches in Royco markets
 */
interface IRDM {
    /**
     * @notice Computes the distribution of total rewards that should be allocated to the senior and junior tranches of a Royco market
     * @param _marketID The unique identifier for the Royco market (may be used for market-specific logic)
     * @param _stTotalAssets The total assets in the senior tranche
     * @param _jtTotalAssets The total assets in the junior tranche, serving as first loss capital
     * @param _coverageWAD The percentage of the total NAV that is expected to be covered by the junior tranche, scaled by WAD
     * @return jtRewardPercentageWAD The percentage of the senior's NAV appreciation allocated to the junior tranche, scaled by WAD
     *                               It is implied that (WAD - jtRewardPercentageWAD) will be the percentage allocated to the senior tranche
     */
    function getRewardDistribution(
        bytes32 _marketID,
        uint256 _stTotalAssets,
        uint256 _jtTotalAssets,
        uint256 _coverageWAD
    )
        external
        returns (uint256 jtRewardPercentageWAD);
}
