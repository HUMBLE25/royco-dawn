// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract Royco {
    constructor(address _owner) {}

    function createMarket(
        address _kernel,
        address _expectedLossWAD,
        address _collateralAsset,
        address _collateralPriceFeedUSD,
        address _irm,
        uint256 _maxLtv,
        uint256 _lltv
    ) external {
        // Deploys the senior tranche configured with the specified kernel

        // Sets up the junior tranche the specified parameters
    }

    function supplySeniorTranche() external {}
}
