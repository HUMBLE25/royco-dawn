// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20, SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IRDM } from "./interfaces/IRDM.sol";
import { IRoycoTranche } from "./interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "./libraries/ConstantsLib.sol";
import { CreateMarketParams, Market, TrancheType, TypesLib } from "./libraries/Types.sol";
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
    error ONLY_MARKET_TRANCHE();
    error INVALID_COVERAGE();

    constructor(address _owner, address _RoycoSTImplementation, address _RoycoJTImplementation) RoycoSTFactory(_RoycoSTImplementation) { }

    function createMarket(CreateMarketParams calldata _params) external returns (bytes32 marketId) {
        marketId = _params.Id();

        Market storage market = marketIdToMarket[marketId];
        require(market.seniorTranche == address(0), MARKET_EXISTS());
        require(_params.coverageWAD > 0.01e18 && _params.coverageWAD <= ConstantsLib.WAD, INVALID_COVERAGE());

        // Set the expected loss for this market
        // This set the minimum ratio between the junior and senior tranche
        market.coverageWAD = _params.coverageWAD;
        market.rdm = _params.rdm;

        // Deploy the senior tranche
        address seniorTranche =
            market.seniorTranche = _deploySeniorTranche(_params.stParams, _params.asset, _params.owner, marketId, _params.coverageWAD, address(0));
    }

    function previewSyncTrancheNAVs(bytes32 _marketId)
        public
        view
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV)
    {
        // Get the market by its ID
        Market storage market = marketIdToMarket[_marketId];

        // Preview the accrual of the yield distribution owed to JT since the last tranche interaction
        uint256 twJTYieldShareAccruedWAD = _previewJTYieldShareAccrual(_marketId, market);

        // Preview the raw and coverage adjusted (effective) NAVs of each tranche
        (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV,) = _previewEffecitveNAVs(market, twJTYieldShareAccruedWAD);
    }

    function syncTrancheNAVs(
        bytes32 _marketId,
        int256 _rawNAVDelta
    )
        external
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV)
    {
        // Get the market by its ID
        Market storage market = marketIdToMarket[_marketId];

        // Check that the caller is one of the market's tranches if they are asserting a NAV delta
        bool stSyncing;
        require(msg.sender == market.juniorTranche || (stSyncing = (msg.sender == market.seniorTranche)) || _rawNAVDelta == 0, ONLY_MARKET_TRANCHE());

        // Accrue the yield distribution owed to JT since the last tranche interaction
        uint256 twJTYieldShareAccruedWAD = market.twJTYieldShareAccruedWAD = _previewJTYieldShareAccrual(_marketId, market);
        market.lastAccrualTimestamp = uint32(block.timestamp);

        // Preview the raw and coverage adjusted (effective) NAVs of each tranche
        bool yieldDistributed;
        (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, yieldDistributed) = _previewEffecitveNAVs(market, twJTYieldShareAccruedWAD);
        // If yield was distributed, reset the accumulator and update the last yield distribution timestamp
        if (yieldDistributed) {
            delete market.twJTYieldShareAccruedWAD;
            market.lastDistributionTimestamp = uint32(block.timestamp);
        }

        // Apply the effect of any deposit or withdrawal after this sync to ensure the checkpoints reflect the post-op tranche state
        market.lastSeniorRawNAV = stSyncing ? _applyDelta(stRawNAV, _rawNAVDelta) : stRawNAV;
        market.lastJuniorRawNAV = !stSyncing ? _applyDelta(jtRawNAV, _rawNAVDelta) : jtRawNAV;
        market.lastSeniorEffectiveNAV = stSyncing ? _applyDelta(stEffectiveNAV, _rawNAVDelta) : stEffectiveNAV;
        market.lastJuniorEffectiveNAV = !stSyncing ? _applyDelta(jtEffectiveNAV, _rawNAVDelta) : jtEffectiveNAV;
    }

    function _previewEffecitveNAVs(
        Market storage _market,
        uint256 _twJTYieldShareAccruedWAD
    )
        internal
        view
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV, bool yieldDistributed)
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
            if (elapsed == 0) return (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, false);
            uint256 jtYieldShareWAD = _twJTYieldShareAccruedWAD / elapsed;
            // Apply the yield split: adding each tranche's share of earnings to their effective NAVs
            uint256 yield = uint256(deltaST);
            uint256 jtYield = yield.mulDiv(jtYieldShareWAD, ConstantsLib.WAD, Math.Rounding.Floor);
            jtEffectiveNAV += jtYield;
            stEffectiveNAV += (yield - jtYield);
            yieldDistributed = true;
        }
    }

    function _previewJTYieldShareAccrual(bytes32 _marketId, Market storage _market) internal view returns (uint192) {
        // Get the last update timestamp
        uint256 lastUpdate = _market.lastAccrualTimestamp;
        if (lastUpdate == 0) return _market.twJTYieldShareAccruedWAD;

        // Compute the elapsed time since the last update
        uint256 elapsed = block.timestamp - lastUpdate;
        // Preemptively return if last accrual was in the same block
        if (elapsed == 0) return _market.twJTYieldShareAccruedWAD;

        // Get the instantaneous JT yield share, scaled by WAD
        uint256 jtYieldShareWAD = IRDM(_market.rdm).getJTYieldShare(_marketId, _market.lastSeniorRawNAV, _market.lastJuniorRawNAV, _market.coverageWAD);
        // Apply the accural of JT yield share to the accumulator, weighted by the time elapsed
        return (_market.twJTYieldShareAccruedWAD + uint192(jtYieldShareWAD * elapsed));
    }

    function _applyDelta(uint256 _nav, int256 _delta) internal pure returns (uint256) {
        if (_delta == 0) return _nav;
        return _delta > 0 ? _nav + uint256(_delta) : Math.saturatingSub(_nav, uint256(-_delta));
    }
}
