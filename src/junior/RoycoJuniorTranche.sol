// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20, SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRoycoOracle} from "../interfaces/IRoycoOracle.sol";

contract RoycoJuniorTranche {
    using SafeERC20 for IERC20;

    uint256 public valueInsuredUSD;

    uint256 public totalCommitmentsUSD;

    uint256 public policyEndTimestamp;

    address collateralAsset;
    address priceFeedUSD;
    uint96 precisionFactor;
    uint64 maxLtv;
    uint64 lltv;
    uint128 maxCommitmentsUSD;

    struct Position {
        uint256 collateralAmount;
        uint256 usdCommitment;
    }

    mapping(address user => Position position) userToPosition;

    error InvalidCollateralAsset();

    constructor(
        address _owner,
        uint256 _valueInsuredUSD,
        address[] memory _collateralAssets,
        address[] memory _collateralPriceFeedsUSD,
        uint256[] memory _maxLtvs,
        uint256[] memory _lltvs,
        uint256 _policyDuration
    ) {}

    function supply(uint256 _collateralAmount, uint256 _commitmentUSD) external {
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), _collateralAmount);

        uint256 collateralValueUSD = _collateralAmount * IRoycoOracle(priceFeedUSD).getAssetPriceUSD() / precisionFactor;

        require(collateralValueUSD >= _commitmentUSD);

        totalCommitmentsUSD += _commitmentUSD;
    }

    function withdraw() external {}
}
