// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../../../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../../../libraries/RoycoKernelStorageLib.sol";
import { MarketState } from "../../../libraries/Types.sol";
import { Math, NAV_UNIT, TRANCHE_UNIT, UnitsMathLib } from "../../../libraries/Units.sol";
import { AssetClaims, IRoycoKernel, RoycoKernel, SyncedAccountingState, TrancheType, ZERO_NAV_UNITS } from "../RoycoKernel.sol";
import { ERC4626_JT_Kernel } from "../junior/ERC4626_JT_Kernel.sol";
import { ERC4626_ST_Kernel } from "../senior/ERC4626_ST_Kernel.sol";

/**
 * @title ERC4626_ST_ERC4626_JT_Kernel
 * @dev This contract functions as a base kernel for all kernels that deploy the senior and junior tranches ERC4626 compliant vaults
 */
abstract contract ERC4626_ST_ERC4626_JT_Kernel is ERC4626_ST_Kernel, ERC4626_JT_Kernel {
    using UnitsMathLib for TRANCHE_UNIT;

    /// @notice Constructor for the ERC4626_ST_ERC4626_JT_Kernel
    /// @param _stVault The address of the ERC4626 compliant vault that the senior tranche will deploy into
    /// @param _jtVault The address of the ERC4626 compliant vault that the junior tranche will deploy into
    constructor(
        address _seniorTranche,
        address _juniorTranche,
        address _stVault,
        address _jtVault
    )
        RoycoKernel(_seniorTranche, IRoycoVaultTranche(_seniorTranche).asset(), _juniorTranche, IRoycoVaultTranche(_juniorTranche).asset())
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
    /// @dev ST Withdrawals are allowed in the following market states: PERPETUAL
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

        // If the market is in a state where ST withdrawals are not allowed, return zero claims
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

