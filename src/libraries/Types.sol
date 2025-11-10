// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

struct JuniorTranche {
    uint256 totalCommitments;
    address commitmentAsset;
    address collateralAsset;
    address collateralAssetPriceFeed;
    address ydm;
    uint96 lctv;
    mapping(address user => JuniorTranchePosition position) userToPosition;
}

/// @notice Represents a user's position in this junior tranche
/// @custom:field collateralBalance - The user's balance of the collateral asset
/// @custom:field commitmentBalance - The user's balance of the commitment asset (only non-zero after a liquidation has occured)
/// @custom:field commitmentMade - The user's commitment to this tranche - backed by their collateral and commitment asset balances
struct JuniorTranchePosition {
    uint256 collateralBalance;
    uint256 commitmentBalance;
    uint256 commitmentMade;
}

struct Market {
    uint96 expectedLossWAD;
    address seniorTranche;
    JuniorTranche juniorTranche;
}
