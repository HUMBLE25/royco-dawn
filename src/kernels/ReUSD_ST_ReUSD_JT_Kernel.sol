// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IInsuranceCapitalLayer } from "../interfaces/external/reUSD/IInsuranceCapitalLayer.sol";
import { RAY } from "../libraries/Constants.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { IdenticalAssetsOracleQuoter } from "./base/quoter/base/IdenticalAssetsOracleQuoter.sol";
import {
    YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel
} from "./base/recipe/YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel.sol";

/**
 * @title ReUSD_ST_ReUSD_JT_Kernel
 * @author Waymont
 * @notice The senior and junior tranches transfer in reUSD
 * @notice The NAV can be expressed in any quote token supported by reUSD's Insurance Capital Layer (ICL) or manually fixed to an admin set oracle input
 * @dev https://docs.re.xyz/insurance-capital-layers/what-is-reusd
 */
contract ReUSD_ST_ReUSD_JT_Kernel is YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel {
    /// @notice The price multiplier to convert reUSD to the quote token (NAV units)
    uint256 constant PRICE_MULTIPLIER = 10 ** 12;

    /// @notice The address of the reUSD token
    address public immutable REUSD;

    /// @notice The address of the token in which the NAV is expressed (typically USDC)
    address public immutable REUSD_USD_QUOTE_TOKEN;

    /// @notice The address of the reUSD insurance capital layer
    address public immutable INSURANCE_CAPITAL_LAYER;

    /**
     * @notice Constructs the Royco kernel
     * @param _params The standard construction parameters for the Royco kernel
     * @param _reusd The address of the reUSD token
     * @param _reusdUsdQuoteToken The address of the token in which the NAV is expressed in
     * @param _insuranceCapitalLayer The address of the reUSD insurance capital layer
     */
    constructor(
        RoycoKernelConstructionParams memory _params,
        address _reusd,
        address _reusdUsdQuoteToken,
        address _insuranceCapitalLayer
    )
        YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel(_params)
    {
        // Set the reUSD specific state
        require(_reusd != address(0) && _reusdUsdQuoteToken != address(0) && _insuranceCapitalLayer != address(0), NULL_ADDRESS());
        REUSD = _reusd;
        REUSD_USD_QUOTE_TOKEN = _reusdUsdQuoteToken;
        INSURANCE_CAPITAL_LAYER = _insuranceCapitalLayer;
    }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     */
    function initialize(RoycoKernelInitParams calldata _params) external initializer {
        // The initial conversion rate is set to the sentinel value so that the reUSD -> REUSD_USD_QUOTE_TOKEN conversion rate is queried directly from the insurance capital layer
        __YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel_init(_params, SENTINEL_CONVERSION_RATE);
    }

    /// @inheritdoc IdenticalAssetsOracleQuoter
    function _getConversionRateFromOracle() internal view override returns (uint256) {
        // Convert 1e9 reUSD (reUSD has 18 decimals of precision) to the quote token (NAV units)
        // This ensures we maximize the precision of the NAV as compared to converting 1 reUSD to NAV units and scaling to RAY precision
        // We multiply the resultant price by a price multiplier 10 ** 12 to compensate for the precision difference betwen USDC and reUSD
        return IInsuranceCapitalLayer(INSURANCE_CAPITAL_LAYER).convertFromShares(REUSD_USD_QUOTE_TOKEN, RAY) * PRICE_MULTIPLIER;
    }
}
