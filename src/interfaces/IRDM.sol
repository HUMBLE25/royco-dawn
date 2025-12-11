// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IRDM - Reward Distribution Model Interface
 * @notice Interface for reward distribution models that determine how ST yield is distributed between tranches in Royco markets
 */
interface IRDM {
    /**
     * @notice Returns a Royco market's percentage of ST yield that should be allocated to its JT
     * @param _stRawNAV The raw net asset value of the senior tranche invested assets
     * @param _jtRawNAV The raw net asset value of the junior tranche invested assets
     * @param _betaWAD The JT's sensitivity to the same downside stress that affects ST scaled by WAD
     *                 For example, beta is 0 when JT is in the RFR and 1 when JT is in the same opportunity as senior
     * @param _coverageWAD The ratio of current exposure that is expected to be covered by the junior capital scaled by WAD
     * @param _jtEffectiveNAV The junior tranche net asset value after applying provided coverage, JT yield, ST yield distribution, and JT losses
     * @return jtYieldShareWAD The percentage of the senior's NAV appreciation allocated to the junior tranche, scaled by WAD
     *                         It is implied that (WAD - jtRewardPercentageWAD) will be the percentage allocated to the senior tranche
     */
    function getJTYieldShare(
        uint256 _stRawNAV,
        uint256 _jtRawNAV,
        uint256 _betaWAD,
        uint256 _coverageWAD,
        uint256 _jtEffectiveNAV
    )
        external
        view
        returns (uint256 jtYieldShareWAD);
}
