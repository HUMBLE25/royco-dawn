// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20, SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IRoycoOracle } from "./interfaces/IRoycoOracle.sol";
import { ConstantsLib } from "./libraries/ConstantsLib.sol";
import { ErrorsLib } from "./libraries/ErrorsLib.sol";
import { EventsLib } from "./libraries/EventsLib.sol";
import { JuniorTranche, JuniorTranchePosition, Market } from "./libraries/Types.sol";

contract Royco {
    using SafeERC20 for IERC20;
    using Math for uint256;

    mapping(bytes32 marketId => Market market) marketIdToMarket;

    constructor(address _owner) { }

    function createMarket(
        address _kernel,
        uint96 _expectedLossWAD,
        address _commitmentAsset,
        address _collateralAsset,
        address _collateralAssetPriceFeed,
        address _ydm,
        uint96 _lctv
    )
        external
        returns (bytes32 marketId)
    {
        marketId = keccak256(abi.encode(_kernel, _expectedLossWAD, _commitmentAsset, _collateralAsset, _collateralAssetPriceFeed, _ydm, _lctv));

        Market storage market = marketIdToMarket[marketId];
        require(market.seniorTranche == address(0), ErrorsLib.MARKET_EXISTS());
        require(_expectedLossWAD <= ConstantsLib.WAD, ErrorsLib.EXPECTED_LOSS_EXCEEDS_MAX());

        // Set the expected loss for this market
        // This set the minimum ratio between the junior and senior tranche
        market.expectedLossWAD = _expectedLossWAD;

        // TODO: Deploy the senior tranche configured with the specified kernel

        // Setup the Junior Tranche with the specified parameters
        market.juniorTranche.commitmentAsset = _commitmentAsset;
        market.juniorTranche.collateralAsset = _collateralAsset;
        market.juniorTranche.collateralAssetPriceFeed = _collateralAssetPriceFeed;
        market.juniorTranche.ydm = _ydm;
        market.juniorTranche.lctv = _lctv;

        emit EventsLib.MarketCreated(_kernel, _commitmentAsset, _collateralAsset, _expectedLossWAD, _collateralAssetPriceFeed, _ydm, _lctv, marketId);
    }

    function addCollateral(bytes32 _marketId, uint256 _collateralAmount, address _onBehalfOf) external {
        // Retrieve and check the existence of the market
        Market storage market = marketIdToMarket[_marketId];
        require(market.seniorTranche != address(0), ErrorsLib.NONEXISTANT_MARKET());

        // Transfer the collateral into the tranche
        IERC20(market.juniorTranche.collateralAsset).safeTransferFrom(msg.sender, address(this), _collateralAmount);

        // Update the user's collateral amount
        market.juniorTranche.userToPosition[_onBehalfOf].collateralBalance += _collateralAmount;

        emit EventsLib.CollateralAdded(_marketId, msg.sender, _onBehalfOf, _collateralAmount);
    }

    function removeCollateral(bytes32 _marketId, uint256 _collateralAmount) external {
        // Retrieve and check the existence of the market
        Market storage market = marketIdToMarket[_marketId];
        require(market.seniorTranche != address(0), ErrorsLib.NONEXISTANT_MARKET());

        // Update the user's collateral amount
        JuniorTranchePosition storage position = market.juniorTranche.userToPosition[msg.sender];
        uint256 collateralBalance = (position.collateralBalance -= _collateralAmount);

        // Check that the user's position is healthy after removing the collateral
        require(_isHealthy(market.juniorTranche, collateralBalance, position.commitmentMade), ErrorsLib.POSITION_IS_UNHEALTHY());

        // Transfer the collateral to the user
        IERC20(market.juniorTranche.collateralAsset).safeTransfer(msg.sender, _collateralAmount);

        emit EventsLib.CollateralRemoved(_marketId, msg.sender, _collateralAmount);
    }

    function makeCommitment(bytes32 _marketId, uint256 _commitmentAmount) external {
        Market storage market = marketIdToMarket[_marketId];
        require(market.seniorTranche != address(0), ErrorsLib.NONEXISTANT_MARKET());

        // Update the user's position accouting and cache it
        JuniorTranchePosition storage position = market.juniorTranche.userToPosition[msg.sender];
        uint256 totalCommitmentAmount = (position.commitmentMade += _commitmentAmount);

        // Check that the user's position is healthy post-commitment
        require(_isHealthy(market.juniorTranche, position.collateralBalance, totalCommitmentAmount), ErrorsLib.POSITION_IS_UNHEALTHY());

        // Increase the total commitments made to this tranche
        market.juniorTranche.totalCommitments += _commitmentAmount;

        emit EventsLib.CommitmentMade(_marketId, msg.sender, _commitmentAmount);
    }

    function withdrawCommitment(bytes32 _marketId, uint256 _commitmentAmount) external {
        Market storage market = marketIdToMarket[_marketId];
        require(market.seniorTranche != address(0), ErrorsLib.NONEXISTANT_MARKET());

        // Update the user's position accouting and cache it
        market.juniorTranche.userToPosition[msg.sender].commitmentMade -= _commitmentAmount;

        // Increase the total commitments made to this tranche
        market.juniorTranche.totalCommitments -= _commitmentAmount;

        emit EventsLib.CommitmentWithdrawn(_marketId, msg.sender, _commitmentAmount);
    }

    function _isHealthy(JuniorTranche storage _juniorTranche, uint256 _collateralBalance, uint256 _commitmentMade) internal returns (bool) {
        // Compute the USD value of their collateral
        uint256 collateralValueInCommitmentAsset = _computeCollateralValue(_juniorTranche, _collateralBalance);
        // Compute the maximum healthy commitment given the collateral value and the LCTV
        uint256 maxCommitment = collateralValueInCommitmentAsset.mulDiv(_juniorTranche.lctv, ConstantsLib.WAD, Math.Rounding.Floor);
        // Ensure the total commitments made by this user are less than the maximum
        return maxCommitment >= _commitmentMade;
    }

    function _computeCollateralValue(JuniorTranche storage _juniorTranche, uint256 _collateralAmount) internal returns (uint256) {
        return _collateralAmount.mulDiv(IRoycoOracle(_juniorTranche.collateralAssetPriceFeed).getPrice(), ConstantsLib.RAY, Math.Rounding.Floor);
    }
}
