// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoKernelState } from "../../libraries/RoycoKernelStorageLib.sol";
import { AssetClaims, ExecutionModel, RequestRedeemSharesBehavior, SyncedAccountingState } from "../../libraries/Types.sol";
import { TrancheType } from "../../libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT } from "../../libraries/Units.sol";

/**
 * @title IRoycoKernel
 *
 */
interface IRoycoKernel {
    /// @notice Thrown when any of the required initialization params are null
    error NULL_ADDRESS();

    /// @notice Thrown when the caller of a permissioned function isn't the market's senior tranche
    error ONLY_SENIOR_TRANCHE();

    /// @notice Thrown when the caller of a permissioned function isn't the market's junior tranche
    error ONLY_JUNIOR_TRANCHE();

    function ST_REQUEST_REDEEM_SHARES_BEHAVIOR() external pure returns (RequestRedeemSharesBehavior);
    function JT_REQUEST_REDEEM_SHARES_BEHAVIOR() external pure returns (RequestRedeemSharesBehavior);

    function ST_INCREASE_NAV_EXECUTION_MODEL() external pure returns (ExecutionModel);
    function ST_DECREASE_NAVAL_EXECUTION_MODEL() external pure returns (ExecutionModel);

    function JT_INCREASE_NAV_EXECUTION_MODEL() external pure returns (ExecutionModel);
    function JT_DECREASE_NAVAL_EXECUTION_MODEL() external pure returns (ExecutionModel);

    function getSTRawNAV() external view returns (NAV_UNIT nav);
    function getJTRawNAV() external view returns (NAV_UNIT nav);

    function getSTTotalEffectiveAssets() external view returns (AssetClaims memory claims);
    function getJTTotalEffectiveAssets() external view returns (AssetClaims memory claims);

    function syncTrancheNAVs(TrancheType _trancheType) external returns (SyncedAccountingState memory state, AssetClaims memory claims);

    function previewSyncTrancheNAVs(TrancheType _trancheType) external view returns (SyncedAccountingState memory state, AssetClaims memory claims);

    function stMaxDeposit(address _receiver) external view returns (TRANCHE_UNIT assets);

    function stMaxWithdrawableAssets(address _owner) external view returns (NAV_UNIT maxWithdrawableNAV);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function stDeposit(TRANCHE_UNIT _assets, address _caller, address _receiver) external returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt);

    function stRedeem(uint256 _shares, address _controller, address _receiver) external returns (AssetClaims memory claims);

    function jtMaxDeposit(address _receiver) external view returns (TRANCHE_UNIT assets);

    function jtMaxWithdrawableAssets(address _owner) external view returns (NAV_UNIT maxWithdrawableNAV);

    /// @notice Converts the specified ST assets denominated in its tranche units to the kernel's NAV units
    /// @param _stAssets The ST assets denominated in tranche units to convert to the kernel's NAV units
    /// @return The specified ST assets denominated in its tranche units converted to the kernel's NAV units
    function stConvertTrancheUnitsToNAVUnits(TRANCHE_UNIT _stAssets) external view returns (NAV_UNIT);

    /// @notice Converts the specified JT assets denominated in its tranche units to the kernel's NAV units
    /// @param _jtAssets The JT assets denominated in tranche units to convert to the kernel's NAV units
    /// @return The specified JT assets denominated in its tranche units converted to the kernel's NAV units
    function jtConvertTrancheUnitsToNAVUnits(TRANCHE_UNIT _jtAssets) external view returns (NAV_UNIT);

    /// @notice Converts the specified assets denominated in the kernel's NAV units to assets denominated in ST's tranche units
    /// @param _navAssets The NAV of the assets denominated in the kernel's NAV units to convert to assets denominated in ST's tranche units
    /// @return The specified NAV of the assets denominated in the kernel's NAV units converted to assets denominated in ST's tranche units
    function stConvertNAVUnitsToTrancheUnits(NAV_UNIT _navAssets) external view returns (TRANCHE_UNIT);

    /// @notice Converts the specified assets denominated in the kernel's NAV units to assets denominated in JT's tranche units
    /// @param _navAssets The NAV of the assets denominated in the kernel's NAV units to convert to assets denominated in JT's tranche units
    /// @return The specified NAV of the assets denominated in the kernel's NAV units converted to assets denominated in JT's tranche units
    function jtConvertNAVUnitsToTrancheUnits(NAV_UNIT _navAssets) external view returns (TRANCHE_UNIT);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function jtDeposit(TRANCHE_UNIT _assets, address _caller, address _receiver) external returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt);

    function jtRedeem(uint256 _shares, address _controller, address _receiver) external returns (AssetClaims memory claims);

    function getState() external view returns (RoycoKernelState memory);
}
