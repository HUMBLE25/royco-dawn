// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20, SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IRoycoLiquidator } from "./interfaces/IRoycoLiquidator.sol";
import { IRoycoOracle } from "./interfaces/IRoycoOracle.sol";
import { ConstantsLib } from "./libraries/ConstantsLib.sol";
import { ErrorsLib } from "./libraries/ErrorsLib.sol";
import { EventsLib } from "./libraries/EventsLib.sol";
import { CreateMarketParams, JuniorTranche, JuniorTranchePosition, Market, TypesLib } from "./libraries/Types.sol";
import { RoycoSeniorTrancheFactory } from "./vault/RoycoSeniorTrancheFactory.sol";

contract Royco is RoycoSeniorTrancheFactory {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using TypesLib for CreateMarketParams;

    mapping(bytes32 marketId => Market market) marketIdToMarket;

    mapping(uint96 lctv => bool enabled) public lctvToEnabled;

    constructor(address _owner, address _roycoSeniorTrancheImplementation) RoycoSeniorTrancheFactory(_roycoSeniorTrancheImplementation) { }

    function createMarket(CreateMarketParams calldata _params) external returns (bytes32 marketId) {
        marketId = _params.hash();

        Market storage market = marketIdToMarket[marketId];
        require(market.seniorTranche == address(0), ErrorsLib.MARKET_EXISTS());
        require(_params.expectedLossWAD <= ConstantsLib.WAD, ErrorsLib.EXPECTED_LOSS_EXCEEDS_MAX());

        // Set the expected loss for this market
        // This set the minimum ratio between the junior and senior tranche
        market.expectedLossWAD = _params.expectedLossWAD;

        // TODO: Deploy the senior tranche configured with the specified kernel
        address seniorTranche = market.seniorTranche = _deployVault(
            _params.stName,
            _params.stSymbol,
            _params.stOwner,
            _params.stKernel,
            _params.commitmentAsset,
            _params.stFeeClaimant,
            _params.stYieldFeeBPS,
            _params.jtVault,
            _params.jtTrancheCoverageFactorBPS,
            _params.stKernelInitParams
        );

        // Setup the Junior Tranche with the specified parameters
        market.juniorTranche.commitmentAsset = _params.commitmentAsset;
        market.juniorTranche.collateralAsset = _params.collateralAsset;
        market.juniorTranche.collateralAssetPriceFeed = _params.collateralAssetPriceFeed;
        market.juniorTranche.ydm = _params.ydm;
        market.juniorTranche.lctv = _params.lctv;

        emit EventsLib.MarketCreated(
            seniorTranche,
            _params.commitmentAsset,
            _params.collateralAsset,
            _params.expectedLossWAD,
            _params.collateralAssetPriceFeed,
            _params.ydm,
            _params.lctv,
            marketId
        );
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

        // TODO: Make sure that the deposits here can still cover expected loss
        // TODO: Implement a withdrawal queue to avoid bank run

        // Update the user's position accouting and cache it
        market.juniorTranche.userToPosition[msg.sender].commitmentMade -= _commitmentAmount;

        // Increase the total commitments made to this tranche
        market.juniorTranche.totalCommitments -= _commitmentAmount;

        emit EventsLib.CommitmentWithdrawn(_marketId, msg.sender, _commitmentAmount);
    }

    function liquidate(bytes32 _marketId, address _user, uint256 _commitmentRepaymentAmount, bytes calldata liquidationCallbackData) external {
        Market storage market = marketIdToMarket[_marketId];
        require(market.seniorTranche != address(0), ErrorsLib.NONEXISTANT_MARKET());

        // Retrieve the user's position
        JuniorTranchePosition storage position = market.juniorTranche.userToPosition[_user];

        // Retrieve the collateral price
        uint256 collateralPrice = IRoycoOracle(market.juniorTranche.collateralAssetPriceFeed).getPrice();

        // Ensure that the user's position is liquidatable (unhealthy)
        require(!_isHealthy(market.juniorTranche, position.collateralBalance, position.commitmentMade, collateralPrice), ErrorsLib.POSITION_IS_HEALTHY());

        // Compute the collateral amount to free in proportion to the repayment on liquidation
        // TODO: Add the liquidation incentive
        uint256 collateralSeizedAmount = _commitmentRepaymentAmount.mulDiv(ConstantsLib.RAY, collateralPrice, Math.Rounding.Floor);

        // Update the user's position: Seize the liquidated collateral and add the corresponding repayment to their liquidated balance
        // NOTE: The user and tranche's commitments remain unchanged following a liquidation
        position.collateralBalance -= collateralSeizedAmount;
        position.liquidatedCommitmentBalance += _commitmentRepaymentAmount;

        // Free the user's collateral to the liquidator
        IERC20(market.juniorTranche.collateralAsset).safeTransfer(msg.sender, collateralSeizedAmount);

        // Execute the callback if specified
        if (liquidationCallbackData.length > 0) {
            IRoycoLiquidator(msg.sender).onRoycoLiquidation(_commitmentRepaymentAmount, collateralSeizedAmount, liquidationCallbackData);
        }

        // Remit the liquidator for the repaid commitment assets
        IERC20(market.juniorTranche.commitmentAsset).safeTransferFrom(msg.sender, address(this), _commitmentRepaymentAmount);

        emit EventsLib.Liquidation(_marketId, _user, msg.sender, _commitmentRepaymentAmount, collateralSeizedAmount);
    }

    function _isHealthy(JuniorTranche storage _juniorTranche, uint256 _collateralBalance, uint256 _commitmentMade) internal view returns (bool) {
        // Retrieve the collateral price in the commitment asset and return the health
        uint256 collateralPrice = IRoycoOracle(_juniorTranche.collateralAssetPriceFeed).getPrice();
        return _isHealthy(_juniorTranche, _collateralBalance, _commitmentMade, collateralPrice);
    }

    function _isHealthy(
        JuniorTranche storage _juniorTranche,
        uint256 _collateralBalance,
        uint256 _commitmentMade,
        uint256 _collateralPrice
    )
        internal
        view
        returns (bool)
    {
        // Compute the collateral value in the commitment asset given the price
        uint256 collateralValue = _collateralBalance.mulDiv(_collateralPrice, ConstantsLib.RAY, Math.Rounding.Floor);
        // Compute the maximum healthy commitment given the collateral value and the LCTV
        uint256 maxCommitment = collateralValue.mulDiv(_juniorTranche.lctv, ConstantsLib.WAD, Math.Rounding.Floor);
        // Ensure the total commitments made by this user are less than the maximum
        return maxCommitment >= _commitmentMade;
    }
}
