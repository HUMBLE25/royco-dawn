// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Represents the state of a Junior Tranche in a Royco Market
/// @custom:field commitmentAsset - The primary asset of the senior tranche
struct JuniorTranche {
    address commitmentAsset;
    address collateralAsset;
    address collateralAssetPriceFeed;
    address ydm;
    uint96 lctv;
    uint256 totalCommitments;
    mapping(address user => JuniorTranchePosition position) userToPosition;
}

/// @notice Represents a user's position in this junior tranche
/// @custom:field collateralBalance - The user's balance of the collateral asset
/// @custom:field liquidatedCommitmentBalance - The user's balance of the commitment asset (only non-zero after a liquidation has occured)
/// @custom:field commitmentMade - The user's commitment to this tranche - backed by their collateral and commitment asset balances
struct JuniorTranchePosition {
    uint256 collateralBalance;
    uint256 liquidatedCommitmentBalance;
    uint256 commitmentMade;
}

struct Market {
    uint96 expectedLossWAD;
    address seniorTranche;
    JuniorTranche juniorTranche;
}

struct CreateMarketParams {
    // General parameters
    address commitmentAsset;
    uint96 expectedLossWAD;
    address ydm;

    // Senior Tranche Specific Parameters
    string stName;
    string stSymbol;
    address stOwner;
    address stKernel;
    address stFeeClaimant;
    address stNavPriceFeed;
    uint24 stYieldFeeBPS;
    bytes stKernelInitParams;

    // Junior Tranche Specific Parameters
    address collateralAsset;
    address collateralAssetPriceFeed;
    uint96 lctv;
}

library TypesLib {
    function hash(CreateMarketParams calldata _createMarketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode(_createMarketParams));
    }
}
