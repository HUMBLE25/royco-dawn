// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library EventsLib {
    event MarketCreated(
        address indexed seniorTranche,
        address indexed commitmentAsset,
        address indexed collateralAsset,
        uint96 expectedLossWAD,
        address collateralAssetPriceFeed,
        address ydm,
        uint96 lctv,
        bytes32 marketId
    );
    event CollateralAdded(bytes32 indexed marketId, address indexed user, address indexed onBehalfOf, uint256 collateralAmount);
    event CollateralRemoved(bytes32 indexed marketId, address indexed user, uint256 collateralAmount);
    event CommitmentMade(bytes32 indexed marketId, address indexed user, uint256 commitmentAmount);
    event CommitmentWithdrawn(bytes32 indexed marketId, address indexed user, uint256 commitmentAmount);
    event Liquidation(
        bytes32 indexed marketId, address indexed user, address indexed _liquidator, uint256 commitmentRepaymentAmount, uint256 seizedCollateralAmount
    );
}
