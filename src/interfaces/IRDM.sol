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
     * @param _stNAV The raw net asset value of the senior tranche
     * @param _jtNAV The raw net asset value of the junior tranche
     * @param _coverageWAD The percentage of the total NAV that is expected to be covered by the junior tranche, scaled by WAD
     * @return jtRewardPercentageWAD The percentage of the senior's NAV appreciation allocated to the junior tranche, scaled by WAD
     *                               It is implied that (WAD - jtRewardPercentageWAD) will be the percentage allocated to the senior tranche
     */
    function getRewardDistribution(bytes32 _marketID, uint256 _stNAV, uint256 _jtNAV, uint256 _coverageWAD) external returns (uint256 jtRewardPercentageWAD);
}
