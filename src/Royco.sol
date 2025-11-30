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

        // Deploy the senior tranche
        address seniorTranche = market.seniorTranche = _deploySeniorTranche(
            _params.stParams, _params.asset, _params.owner, _params.rewardFeeWAD, _params.feeClaimant, _params.rdm, _params.coverageWAD, address(0)
        );
    }

    function updateTrancheAccounting(bytes32 _marketId) external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV) {
        Market storage market = marketIdToMarket[_marketId];

        // _accrueYield();

        // Get the current NAVs of each tranche
        stRawNAV = IRoycoTranche(market.seniorTranche).getNAV();
        jtRawNAV = IRoycoTranche(market.juniorTranche).getNAV();

        // Cache the total assets for each tranche as their last recorded total assets
        stEffectiveNAV = market.lastSeniorProtectedNAV;
        jtEffectiveNAV = market.lastJuniorProtectedNAV;

        // Compute and apply any losses for the junior tranche to its total assets
        uint256 jtLoss = Math.saturatingSub(market.lastJuniorNAV, jtRawNAV);
        if (jtLoss > 0) {
            jtEffectiveNAV = Math.saturatingSub(jtEffectiveNAV, jtLoss);
        }

        // Compute the delta in the seior tranche NAV
        int256 deltaST = int256(stRawNAV) - int256(market.lastSeniorNAV);
        // Senior tranche incurred a loss
        if (deltaST < 0) {
            // Apply the loss to the senior tranche's total assets
            uint256 loss = uint256(-deltaST);
            stEffectiveNAV -= loss;
            // Compute and apply the coverage provided by the junior tranche to the senior tranche
            uint256 coverage = Math.min(loss, jtEffectiveNAV);
            stEffectiveNAV += coverage;
            jtEffectiveNAV -= coverage;
        } else {
            // Senior tranche accrued yield
            // Apply the yield distribution via the RDM
        }

        // Set the tranche checkpoints in persistent storage
        market.lastSeniorNAV = stRawNAV;
        market.lastJuniorNAV = jtRawNAV;
        market.lastSeniorProtectedNAV = stEffectiveNAV;
        market.lastJuniorProtectedNAV = jtEffectiveNAV;
    }

    function _accrueJTYieldShare(bytes32 _marketID, Market storage _market, uint256 _stRawNAV, uint256 _jtRawNAV) internal {
        // Get the last update timestamp
        uint256 lastUpdate = _market.lastJTYieldShareAccrualTimestamp;
        if (lastUpdate == 0) {
            _market.lastJTYieldShareAccrualTimestamp = block.timestamp;
            return;
        }

        // Compute the elapsed time since the last update
        uint256 elapsed = block.timestamp - lastUpdate;
        // Premptively return if last updated in the same block
        if (elapsed == 0) return;

        // Get instantaneous JT yield share, scaled by WAD
        uint256 jtYieldShareWAD = IRDM(_market.rdm).getJTYieldShare(_marketID, _stRawNAV, _jtRawNAV, _market.coverageWAD);

        // Apply the accural of JT yield share to the accumulator, elapsed by the amount of time elapsed
        _market.jtYieldShareAccrued += jtYieldShareWAD * elapsed;
        _market.lastJTYieldShareAccrualTimestamp = block.timestamp;
    }
}
