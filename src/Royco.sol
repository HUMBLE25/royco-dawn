// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20, SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IRDM } from "./interfaces/IRDM.sol";
import { IRoycoTranche } from "./interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "./libraries/ConstantsLib.sol";
import { CreateMarketParams, Market, TypesLib } from "./libraries/Types.sol";
import { UtilsLib } from "./libraries/UtilsLib.sol";
import { RoycoSTFactory } from "./tranches/senior/RoycoSTFactory.sol";

contract Royco is RoycoSTFactory {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using TypesLib for CreateMarketParams;

    mapping(bytes32 marketId => Market market) marketIdToMarket;
    mapping(address st => address jt) seniorTrancheToJuniorTranche;
    mapping(address jt => address st) juniorTrancheToSeniorTranche;

    error MARKET_EXISTS();
    error NONEXISTANT_MARKET();
    error INVALID_coverage();

    constructor(address _owner, address _RoycoSTImplementation, address _RoycoJTImplementation) RoycoSTFactory(_RoycoSTImplementation) { }

    function createMarket(CreateMarketParams calldata _params) external returns (bytes32 marketId) {
        marketId = _params.Id();

        Market storage market = marketIdToMarket[marketId];
        require(market.seniorTranche == address(0), MARKET_EXISTS());
        require(_params.coverageWAD > 0.01e18 && _params.coverageWAD <= ConstantsLib.WAD, INVALID_coverage());

        // Set the expected loss for this market
        // This set the minimum ratio between the junior and senior tranche
        market.coverageWAD = _params.coverageWAD;
        market.rdm = _params.rdm;

        // Deploy the senior tranche
        address seniorTranche = market.seniorTranche = _deploySeniorTranche(
            _params.stParams, _params.asset, _params.owner, _params.rewardFeeWAD, _params.feeClaimant, _params.rdm, _params.coverageWAD, address(0)
        );
    }

    function syncTrancheNAVs(bytes32 _marketId) external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV) {
        // Set the tranche NAV checkpoints in persistent storage
        Market storage market = marketIdToMarket[_marketId];

        // Accrue the yield distribution owed to JT since the last tranche interaction
        _accrueJTYieldShare(_marketId, market);

        // Get the raw and coverage adjusted (effective) NAVs of each tranche
        (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV) = _computeEffecitveNAVs(market);

        // Write the updated tranche NAV checkpoints to persistent storage
        market.lastSeniorRawNAV = stRawNAV;
        market.lastJuniorRawNAV = jtRawNAV;
        market.lastSeniorEffectiveNAV = stEffectiveNAV;
        market.lastJuniorEffectiveNAV = jtEffectiveNAV;
    }

    function _computeEffecitveNAVs(Market storage _market)
        internal
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV)
    {
        // Get the current NAVs of each tranche
        stRawNAV = IRoycoTranche(_market.seniorTranche).getNAV();
        jtRawNAV = IRoycoTranche(_market.juniorTranche).getNAV();

        // Cache the effective NAV for each tranche as their last recorded effective NAV
        stEffectiveNAV = _market.lastSeniorEffectiveNAV;
        jtEffectiveNAV = _market.lastJuniorEffectiveNAV;

        // Compute the delta in the junior tranche NAV
        int256 deltaJT = int256(jtRawNAV) - int256(_market.lastJuniorRawNAV);
        // Apply the loss to the junior tranche's effective NAV
        if (deltaJT < 0) jtEffectiveNAV = Math.saturatingSub(jtEffectiveNAV, uint256(-deltaJT));
        // Junior tranche always keeps all of its appreciation
        else jtEffectiveNAV += uint256(deltaJT);

        // Compute the delta in the senior tranche NAV
        int256 deltaST = int256(stRawNAV) - int256(_market.lastSeniorRawNAV);
        if (deltaST < 0) {
            // Senior tranche incurred a loss
            // Apply the loss to the senior tranche's effective NAV
            uint256 loss = uint256(-deltaST);
            stEffectiveNAV = Math.saturatingSub(stEffectiveNAV, loss);
            // Compute and apply the coverage provided by the junior tranche to the senior tranche
            uint256 coverage = Math.min(loss, jtEffectiveNAV);
            stEffectiveNAV += coverage;
            jtEffectiveNAV -= coverage;
        } else {
            // Senior tranche accrued yield
            // Compute the time weighted average JT share of yield
            uint256 elapsed = block.timestamp - _market.lastDistributionTimestamp;
            // Preemptively return if last yield distribution was in the same block
            if (elapsed == 0) return (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV);
            uint256 jtYieldShareWAD = _market.twJTYieldShareAccruedWAD / elapsed;
            // Apply the yield split: adding each tranche's share of earnings to their effective NAVs
            uint256 yield = uint256(deltaST);
            uint256 jtYield = yield.mulDiv(jtYieldShareWAD, ConstantsLib.WAD, Math.Rounding.Floor);
            jtEffectiveNAV += jtYield;
            stEffectiveNAV += (yield - jtYield);
            // Reset the accumulator and update the last yield distribution timestamp
            delete _market.twJTYieldShareAccruedWAD;
            _market.lastDistributionTimestamp = uint32(block.timestamp);
        }
    }

    function _accrueJTYieldShare(bytes32 _marketId, Market storage _market) internal {
        // Get the last update timestamp
        uint256 lastUpdate = _market.lastAccrualTimestamp;
        if (lastUpdate == 0) {
            _market.lastAccrualTimestamp = uint32(block.timestamp);
            return;
        }

        // Compute the elapsed time since the last update
        uint256 elapsed = block.timestamp - lastUpdate;
        // Preemptively return if last accrual was in the same block
        if (elapsed == 0) return;

        // Get the instantaneous JT yield share, scaled by WAD
        uint256 jtYieldShareWAD = IRDM(_market.rdm).getJTYieldShare(_marketId, _market.lastSeniorRawNAV, _market.lastJuniorRawNAV, _market.coverageWAD);
        // Apply the accural of JT yield share to the accumulator, weighted by the amount of time elapsed
        _market.twJTYieldShareAccruedWAD += uint192(jtYieldShareWAD * elapsed);
        _market.lastAccrualTimestamp = uint32(block.timestamp);
    }
}
