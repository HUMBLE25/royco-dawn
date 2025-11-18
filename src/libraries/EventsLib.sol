// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library EventsLib {
    event MarketCreated(
        address indexed seniorTranche,
        address indexed commitmentAsset,
        address indexed collateralAsset,
        uint96 protectedLossWAD,
        address collateralAssetPriceFeed,
        address rdm,
        uint96 lctv,
        bytes32 marketId
    );
}
