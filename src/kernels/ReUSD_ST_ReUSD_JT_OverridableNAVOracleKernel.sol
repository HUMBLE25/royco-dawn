// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IInsuranceCapitalLayer } from "../interfaces/external/reUSD/IInsuranceCapitalLayer.sol";
import { WAD } from "../libraries/Constants.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { OverridableNAVOracleIdenticalAssetsQuoter } from "./base/quoter/OverridableNAVOracleIdenticalAssetsQuoter.sol";
import {
    YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel
} from "./base/recipe/YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel.sol";

/**
 * @title ReUSD_ST_ReUSD_JT_OverridableNAVOracleKernel
 * @notice The senior and junior tranches transfer in reUSD
 * @dev https://docs.re.xyz/insurance-capital-layers/what-is-reusd
 * @notice Tranche and NAV units are always expressed in the tranche asset's precision. The NAV Unit factors in a conversion rate from the overridable NAV Conversion Rate oracle.
 */
contract ReUSD_ST_ReUSD_JT_OverridableNAVOracleKernel is YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel {
    /// @notice The address of the sNUSD ERC4626 vault
    address public immutable REUSD;
    /// @notice The address of the token in which the NAV is expressed.
    /// @dev REUSD_USD_QUOTE_TOKEN is typically USDC.
    address public immutable REUSD_USD_QUOTE_TOKEN;
    /// @notice The address of the reUSD insurance capital layer
    address public immutable INSURANCE_CAPITAL_LAYER;

    /// @notice Constructor
    /// @param _reusd The address of the reUSD token
    /// @param _reusdUsdQuoteToken The address of the token in which the NAV is expressed.
    /// @param _insuranceCapitalLayer The address of the reUSD insurance capital layer
    /// @dev We enable the tranche unit to NAV unit conversion rate cache to reduce the number of calls to the insurance capital layer during the same call.
    constructor(
        address _seniorTranche,
        address _juniorTranche,
        address _reusd,
        address _reusdUsdQuoteToken,
        address _insuranceCapitalLayer
    )
        YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel(_seniorTranche, _juniorTranche, _reusd)
    {
        REUSD = _reusd;
        REUSD_USD_QUOTE_TOKEN = _reusdUsdQuoteToken;
        INSURANCE_CAPITAL_LAYER = _insuranceCapitalLayer;
    }

    /// @notice Initializes the kernel
    /// @param _params The standard initialization parameters for the Royco Kernel
    function initialize(RoycoKernelInitParams calldata _params) external initializer {
        // We set the price override to 0, so that the reUSD -> REUSD_USD_QUOTE_TOKEN conversion rate is queried from the insurance capital layer
        __YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel_init(_params, 0);
    }

    /// @inheritdoc OverridableNAVOracleIdenticalAssetsQuoter
    function _getTrancheUnitToNAVUnitConversionRateFromOracle() internal view override returns (uint256 ratetrancheUnitToNAVUnitConversionRateWAD) {
        return IInsuranceCapitalLayer(INSURANCE_CAPITAL_LAYER).convertFromShares(REUSD_USD_QUOTE_TOKEN, WAD);
    }
}
