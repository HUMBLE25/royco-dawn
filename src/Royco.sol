// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20, SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ConstantsLib } from "./libraries/ConstantsLib.sol";
import { ErrorsLib } from "./libraries/ErrorsLib.sol";
import { EventsLib } from "./libraries/EventsLib.sol";
import { CreateMarketParams, Market, TypesLib } from "./libraries/Types.sol";
import { RoycoSTFactory } from "./tranches/senior/RoycoSTFactory.sol";

contract Royco is RoycoSTFactory {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using TypesLib for CreateMarketParams;

    mapping(bytes32 marketId => Market market) marketIdToMarket;

    constructor(address _owner, address _RoycoSTImplementation) RoycoSTFactory(_RoycoSTImplementation) { }

    function createMarket(CreateMarketParams calldata _params) external returns (bytes32 marketId) {
        marketId = _params.Id();

        Market storage market = marketIdToMarket[marketId];
        require(market.seniorTranche == address(0), ErrorsLib.MARKET_EXISTS());
        require(_params.protectedLossWAD <= ConstantsLib.WAD, ErrorsLib.EXPECTED_LOSS_EXCEEDS_MAX());

        // Set the expected loss for this market
        // This set the minimum ratio between the junior and senior tranche
        market.protectedLossWAD = _params.protectedLossWAD;

        // Deploy the senior tranche
        address seniorTranche = market.seniorTranche = _deploySeniorTranche(
            _params.stParams, _params.asset, _params.owner, _params.rewardFeeWAD, _params.feeClaimant, _params.rdm, _params.protectedLossWAD, address(0)
        );

        // TODO: Deploy the junior tranche configured with the specified kernel
        // emit EventsLib.MarketCreated(
        //     seniorTranche,
        //     _params.commitmentAsset,
        //     _params.collateralAsset,
        //     _params.protectedLossWAD,
        //     _params.collateralAssetPriceFeed,
        //     _params.rdm,
        //     _params.lctv,
        //     marketId
        // );
    }
}
