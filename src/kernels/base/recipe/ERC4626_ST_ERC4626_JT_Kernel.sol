// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoKernelInitParams } from "../../../libraries/RoycoKernelStorageLib.sol";
import { MarketState } from "../../../libraries/Types.sol";
import { Math, NAV_UNIT, TRANCHE_UNIT, UnitsMathLib } from "../../../libraries/Units.sol";
import { AssetClaims, IRoycoKernel, RoycoKernel, SyncedAccountingState, TrancheType, ZERO_NAV_UNITS } from "../RoycoKernel.sol";
import { ERC4626_JT_Kernel } from "../junior/ERC4626_JT_Kernel.sol";
import { ERC4626_ST_Kernel } from "../senior/ERC4626_ST_Kernel.sol";

/**
 * @title ERC4626_ST_ERC4626_JT_Kernel
 * @author Waymont
 * @dev This contract functions as a base kernel for all kernels that deploy the senior and junior tranches into ERC4626 compliant vaults
 * @dev The concrete implementation must implement or inherit a quoter
 */
abstract contract ERC4626_ST_ERC4626_JT_Kernel is ERC4626_ST_Kernel, ERC4626_JT_Kernel {
    using UnitsMathLib for TRANCHE_UNIT;

    /**
     * @notice Constructs the Royco kernel
     * @param _params The standard construction parameters for the Royco kernel
     * @param _stVault The address of the ERC4626 compliant vault that the senior tranche will deploy into
     * @param _jtVault The address of the ERC4626 compliant vault that the junior tranche will deploy into
     */
    constructor(
        RoycoKernelConstructionParams memory _params,
        address _stVault,
        address _jtVault
    )
        RoycoKernel(_params)
        ERC4626_ST_Kernel(_stVault)
        ERC4626_JT_Kernel(_jtVault)
    { }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     */
    function __ERC4626_ST_ERC4626_JT_Kernel_init(RoycoKernelInitParams calldata _params) internal onlyInitializing {
        // Initialize the base kernel state
        __RoycoKernel_init(_params);
        // Initialize the ERC4626 senior tranche state
        __ERC4626_ST_Kernel_init_unchained();
        // Initialize the ERC4626 junior tranche state
        __ERC4626_JT_Kernel_init_unchained();
    }

    /// @inheritdoc IRoycoKernel
    /// @dev Override this function to prevent double counting of max withdrawable assets when both tranches deploy into the same ERC4626 vault
    function stMaxWithdrawable(address _owner)
        public
        view
        virtual
        override(RoycoKernel)
        returns (NAV_UNIT claimOnStNAV, NAV_UNIT claimOnJtNAV, NAV_UNIT stMaxWithdrawableNAV, NAV_UNIT jtMaxWithdrawableNAV)
    {
        // If both tranches are in different ERC4626 vaults, double counting is not possible
        if (ST_VAULT != JT_VAULT) return super.stMaxWithdrawable(_owner);

        (SyncedAccountingState memory state, AssetClaims memory stNotionalClaims,) = previewSyncTrancheAccounting(TrancheType.SENIOR);

        // If the market is not in a perpetual state, ST withdrawals are disabled
        if (state.marketState != MarketState.PERPETUAL) {
            return (ZERO_NAV_UNITS, ZERO_NAV_UNITS, ZERO_NAV_UNITS, ZERO_NAV_UNITS);
        }

        // Get the total claims the senior tranche has on each tranche's assets
        NAV_UNIT stTotalClaimsNAV = stNotionalClaims.nav;
        if (stTotalClaimsNAV == ZERO_NAV_UNITS) return (ZERO_NAV_UNITS, ZERO_NAV_UNITS, ZERO_NAV_UNITS, ZERO_NAV_UNITS);
        claimOnStNAV = stConvertTrancheUnitsToNAVUnits(stNotionalClaims.stAssets);
        claimOnJtNAV = jtConvertTrancheUnitsToNAVUnits(stNotionalClaims.jtAssets);

        // Get the maximum withdrawable assets for both tranches combined
        // Scale the max withdrawable assets by the percentage claims ST has on each tranche
        TRANCHE_UNIT totalMaxWithdrawableAssets = _stMaxWithdrawableGlobally(_owner);
        stMaxWithdrawableNAV = stConvertTrancheUnitsToNAVUnits(totalMaxWithdrawableAssets.mulDiv(claimOnStNAV, stTotalClaimsNAV, Math.Rounding.Floor));
        jtMaxWithdrawableNAV = jtConvertTrancheUnitsToNAVUnits(totalMaxWithdrawableAssets.mulDiv(claimOnJtNAV, stTotalClaimsNAV, Math.Rounding.Floor));
    }

    /// @inheritdoc IRoycoKernel
    /// @dev Override this function to prevent double counting of max withdrawable assets when both tranches deploy into the same ERC4626 vault
    function jtMaxWithdrawable(address _owner)
        public
        view
        virtual
        override(RoycoKernel)
        returns (NAV_UNIT claimOnStNAV, NAV_UNIT claimOnJtNAV, NAV_UNIT stMaxWithdrawableNAV, NAV_UNIT jtMaxWithdrawableNAV)
    {
        // If both tranches are in different ERC4626 vaults, double counting is not possible
        if (ST_VAULT != JT_VAULT) return super.jtMaxWithdrawable(_owner);

        // Get the total claims the junior tranche has on each tranche's assets
        (SyncedAccountingState memory state, AssetClaims memory jtNotionalClaims,) = previewSyncTrancheAccounting(TrancheType.JUNIOR);
        NAV_UNIT jtTotalClaimsNAV = jtNotionalClaims.nav;
        if (jtTotalClaimsNAV == ZERO_NAV_UNITS) return (ZERO_NAV_UNITS, ZERO_NAV_UNITS, ZERO_NAV_UNITS, ZERO_NAV_UNITS);

        // Get the max withdrawable ST and JT assets in NAV units from the accountant consider coverage requirement
        (, NAV_UNIT stClaimableGivenCoverage, NAV_UNIT jtClaimableGivenCoverage) = _accountant()
            .maxJTWithdrawalGivenCoverage(
                state.stRawNAV,
                state.jtRawNAV,
                stConvertTrancheUnitsToNAVUnits(jtNotionalClaims.stAssets),
                jtConvertTrancheUnitsToNAVUnits(jtNotionalClaims.jtAssets)
            );

        claimOnStNAV = stConvertTrancheUnitsToNAVUnits(jtNotionalClaims.stAssets);
        claimOnJtNAV = jtConvertTrancheUnitsToNAVUnits(jtNotionalClaims.jtAssets);

        // Get the maximum withdrawable assets for both tranches combined
        // Scale the max withdrawable assets by the percentage claims JT has on each tranche
        TRANCHE_UNIT totalMaxWithdrawableAssets = _jtMaxWithdrawableGlobally(_owner);
        stMaxWithdrawableNAV = UnitsMathLib.min(
            stConvertTrancheUnitsToNAVUnits(totalMaxWithdrawableAssets.mulDiv(claimOnStNAV, jtTotalClaimsNAV, Math.Rounding.Floor)), stClaimableGivenCoverage
        );
        jtMaxWithdrawableNAV = UnitsMathLib.min(
            jtConvertTrancheUnitsToNAVUnits(totalMaxWithdrawableAssets.mulDiv(claimOnJtNAV, jtTotalClaimsNAV, Math.Rounding.Floor)), jtClaimableGivenCoverage
        );
    }
}

