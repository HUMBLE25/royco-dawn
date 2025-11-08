// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20, SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IRoycoOracle} from "../interfaces/IRoycoOracle.sol";

contract RoycoJuniorTranche {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @dev Constant for the WAD scaling factor
    uint256 private constant WAD = 1e18;

    /// @dev The collateral asset used to make USD commitments to the junior tranche
    address public immutable COLLATERAL_ASSET;

    /// @dev Represent 1 whole collateral asset
    uint256 private immutable ONE_COLLATERAL_ASSET;

    /// @dev The price feed returning the price of the collateral asset in USD
    address public priceFeedUSD;

    /// @notice The maximum commitment to value the protocol allows a user to open a commitment with
    /// @dev Scaled by WAD
    uint256 public maxCtv;

    /// @notice The liquidation commitment to value at which point a liquidator can seize the collateral by fulfilling the user's commitment
    /// @dev Scaled by WAD
    uint256 public lctv;

    /// @notice The total number of USD commitments securing the corresponding senior tranche
    uint256 public totalCommitmentsUSD;

    /// @notice Represents a user's position in this tranche
    /// @custom:field collateralBalance - The user's balance of the collateral asset
    /// @custom:field usdBalance - The user's USD balance (only non-zero after a liquidation has occured)
    /// @custom:field commitmentUSD - The user's USD commitment to this tranche backed by the collateral and USD balance
    struct Position {
        uint256 collateralBalance;
        uint256 usdBalance;
        uint256 commitmentUSD;
    }

    /// @notice Mapping of users to their positions in this tranche
    mapping(address user => Position position) userToPosition;

    event Commit(address indexed user, address indexed onBehalfOf, uint256 collateralAmount, uint256 commitmentUSD);

    error InvalidCollateralAsset();
    error maxCtvExceeded();

    constructor(address _owner, address _collateralAsset, address _priceFeedUSD, uint256 _maxCtv, uint256 _lctv) {
        COLLATERAL_ASSET = _collateralAsset;
        ONE_COLLATERAL_ASSET = 10 ** IERC20Metadata(_collateralAsset).decimals();

        priceFeedUSD = _priceFeedUSD;
        maxCtv = _maxCtv;
        lctv = _lctv;
    }

    function commit(uint256 _commitmentUSD, uint256 _collateralAmount, address _onBehalfOf) external {
        // Transfer the collateral into the tranche
        IERC20(COLLATERAL_ASSET).safeTransferFrom(msg.sender, address(this), _collateralAmount);

        // Increase the total commitments
        totalCommitmentsUSD += _commitmentUSD;

        // Update the user's position accouting and cache it in local variables
        Position storage position = userToPosition[_onBehalfOf];
        uint256 userCollateralAmount = (position.collateralBalance += _collateralAmount);
        uint256 userCommitmentUSD = (position.commitmentUSD += _commitmentUSD);

        // Ensure that the user's cumulative position doesn't exceed the max configured CTV
        uint256 collateralValueUSD = userCollateralAmount.mulDiv(
            IRoycoOracle(priceFeedUSD).getAssetPriceUSD(), ONE_COLLATERAL_ASSET, Math.Rounding.Floor
        );
        require(collateralValueUSD.mulDiv(maxCtv, WAD, Math.Rounding.Floor) >= userCommitmentUSD, maxCtvExceeded());

        emit Commit(msg.sender, _onBehalfOf, _collateralAmount, _commitmentUSD);
    }
}
