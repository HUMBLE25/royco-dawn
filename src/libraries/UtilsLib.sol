// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

library UtilsLib {
    using Math for uint256;

    /**
     * @notice Computes the utilization of the Royco market given the market's state
     * @dev Utilization = ((ST_NAV + JT_NAV) * COV_%) / JT_NAV
     * @param _stRawNAV The raw net asset value of the senior tranche
     * @param _jtRawNAV The raw net asset value of the junior tranche
     * @param _coverageWAD The percentage of the total NAV that is expected to be covered by the junior tranche at all times, scaled by WAD
     * @return utilization The utilization of the Royco market, scaled by WAD
     */
    function computeUtilization(uint256 _stRawNAV, uint256 _jtRawNAV, uint256 _coverageWAD) internal pure returns (uint256 utilization) {
        // Round in favor the senior tranche
        utilization = (_stRawNAV + _jtRawNAV).mulDiv(_coverageWAD, _jtRawNAV, Math.Rounding.Floor);
    }
}
