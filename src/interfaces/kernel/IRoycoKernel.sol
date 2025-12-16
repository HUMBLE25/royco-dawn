// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoKernelState } from "../../libraries/RoycoKernelStorageLib.sol";
import { AssetClaims, ExecutionModel, RequestRedeemSharesBehavior, SyncedAccountingState } from "../../libraries/Types.sol";
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

    function syncTrancheNAVs() external returns (SyncedAccountingState memory state, AssetClaims memory claims);

    function previewSyncTrancheNAVs() external view returns (SyncedAccountingState memory state, AssetClaims memory claims);

    function stMaxDeposit(address _asset, address _receiver) external view returns (TRANCHE_UNIT assets);

    function stMaxWithdrawableAssets(address _asset, address _owner) external view returns (AssetClaims memory claims);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function stDeposit(address _asset, uint256 _assets, address _caller, address _receiver) external returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt);

    function stRedeem(
        address _asset,
        uint256 _shares,
        uint256 _totalShares,
        address _controller,
        address _receiver
    )
        external
        returns (AssetClaims memory claims);

    function jtMaxDeposit(address _asset, address _receiver) external view returns (TRANCHE_UNIT assets);
    function jtMaxWithdrawableAssets(address _asset, address _owner) external view returns (AssetClaims memory claims);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function jtDeposit(address _asset, uint256 _assets, address _caller, address _receiver) external returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt);

    function jtRedeem(
        address _asset,
        uint256 _shares,
        uint256 _totalShares,
        address _controller,
        address _receiver
    )
        external
        returns (AssetClaims memory claims);

    function getState() external view returns (RoycoKernelState memory);
}
