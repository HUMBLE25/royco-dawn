// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRouter } from "../interfaces/external/neutrl/IRouter.sol";
import { WAD } from "../libraries/Constants.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { OverridableNAVOracleIdenticalAssetsQuoter } from "./base/quoter/OverridableNAVOracleIdenticalAssetsQuoter.sol";
import {
    ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel
} from "./base/recipe/ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel.sol";

/**
 * @title NeutrlSNUSD_ST_NeutrlSNUSD_JT_OverridableNAVOracleKernel
 * @notice The senior and junior tranches are deployed into a Neutrl sNUSD ERC4626 compliant vault
 * @notice The two tranches can be deployed into the same Neutrl sNUSD vault
 * @notice Tranche and NAV units are always expressed in the tranche asset's precision. The NAV Unit factors in a conversion rate from the overridable NAV Conversion Rate oracle.
 */
contract NeutrlSNUSD_ST_NeutrlSNUSD_JT_OverridableNAVKernel is ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel {
    /// @notice The address of the token in which the NAV is expressed.
    /// @dev The NAV of an amount a of sNUSD is defined as sNUSD.convertSharesToAssets(a) * (value of 1 NUSD in NUSD_USD_QUOTE_TOKEN)
    /// @dev NUSD_USD_QUOTE_TOKEN is typically USDC.
    address public immutable NUSD_USD_QUOTE_TOKEN;
    /// @notice The address of the Neutrl Router
    address public immutable NEUTRL_ROUTER;

    /// @notice Constructor
    /// @param _seniorTranche The address of the senior tranche
    /// @param _juniorTranche The address of the junior tranche
    /// @param _snUSDVault The address of the SNUSD vault
    /// @param _nusdUsdQuoteToken The address of the token in which the NAV is expressed.
    /// @param _neutrlRouter The address of the Neutrl Router
    /// @dev NUSD_USD_QUOTE_TOKEN is typically USDC.
    constructor(
        address _seniorTranche,
        address _juniorTranche,
        address _snUSDVault,
        address _nusdUsdQuoteToken,
        address _neutrlRouter
    )
        ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel(_seniorTranche, _juniorTranche, _snUSDVault, _snUSDVault)
    {
        NUSD_USD_QUOTE_TOKEN = _nusdUsdQuoteToken;
        NEUTRL_ROUTER = _neutrlRouter;
    }

    /// @notice Initializes the kernel
    /// @param _params The standard initialization parameters for the Royco Kernel
    function initialize(RoycoKernelInitParams calldata _params) external initializer {
        // We set the price override to 0, so that the NUSD -> NUSD_USD_QUOTE_TOKEN conversion rate is queried from the Neutrl Router
        __ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel_init(_params, 0);
    }

    /// @inheritdoc OverridableNAVOracleIdenticalAssetsQuoter
    function _getTrancheUnitToNAVUnitConversionRateFromOracle() internal view override returns (uint256 ratetrancheUnitToNAVUnitConversionRateWAD) {
        return IRouter(NEUTRL_ROUTER).quoteRedemption(NUSD_USD_QUOTE_TOKEN, WAD);
    }
}
