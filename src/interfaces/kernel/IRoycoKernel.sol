// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoKernelState } from "../../libraries/RoycoKernelStorageLib.sol";
import { ExecutionModel, RequestRedeemSharesBehavior, SyncedNAVsPacket } from "../../libraries/Types.sol";

/**
 * @title IRoycoKernel
 *
 */
interface IRoycoKernel {
    struct AssetBreakdown {
        uint256 totalAssetsInNAVUnits;
        uint256 stAssets;
        uint256 jtAssets;
    }

    /// @notice Thrown when any of the required initialization params are null
    error NULL_ADDRESS();

    /// @notice Thrown when the caller of a permissioned function isn't the market's senior tranche
    error ONLY_SENIOR_TRANCHE();

    /// @notice Thrown when the caller of a permissioned function isn't the market's junior tranche
    error ONLY_JUNIOR_TRANCHE();

    function ST_REQUEST_REDEEM_SHARES_BEHAVIOR() external pure returns (RequestRedeemSharesBehavior);
    function JT_REQUEST_REDEEM_SHARES_BEHAVIOR() external pure returns (RequestRedeemSharesBehavior);

    function ST_DEPOSIT_EXECUTION_MODEL() external pure returns (ExecutionModel);
    function ST_WITHDRAWAL_EXECUTION_MODEL() external pure returns (ExecutionModel);

    function JT_DEPOSIT_EXECUTION_MODEL() external pure returns (ExecutionModel);
    function JT_WITHDRAWAL_EXECUTION_MODEL() external pure returns (ExecutionModel);

    function getSTRawNAV() external view returns (uint256 assetsInNAVUnits);
    function getJTRawNAV() external view returns (uint256 assetsInNAVUnits);

    function getSTTotalEffectiveAssets() external view returns (AssetBreakdown memory breakdown);
    function getJTTotalEffectiveAssets() external view returns (AssetBreakdown memory breakdown);

    function syncTrancheNAVs() external returns (SyncedNAVsPacket memory packet);

    function previewSyncTrancheNAVs() external view returns (SyncedNAVsPacket memory packet);

    function stMaxDeposit(address _asset, address _receiver) external view returns (uint256 assets);

    function stMaxWithdrawableAssets(address _asset, address _owner) external view returns (AssetBreakdown memory breakdown);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function stDeposit(
        address _asset,
        uint256 _assets,
        address _caller,
        address _receiver
    )
        external
        returns (uint256 valueAllocatedInNAVUnits, uint256 effectiveNAVToMintAt);

    function stRedeem(
        address _asset,
        uint256 _shares,
        uint256 _totalShares,
        address _controller,
        address _receiver
    )
        external
        returns (AssetBreakdown memory breakdown);

    function jtMaxDeposit(address _asset, address _receiver) external view returns (uint256 assets);
    function jtMaxWithdrawableAssets(address _asset, address _owner) external view returns (AssetBreakdown memory breakdown);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function jtDeposit(
        address _asset,
        uint256 _assets,
        address _caller,
        address _receiver
    )
        external
        returns (uint256 valueAllocatedInNAVUnits, uint256 effectiveNAVToMintAt);

    function jtRedeem(
        address _asset,
        uint256 _shares,
        uint256 _totalShares,
        address _controller,
        address _receiver
    )
        external
        returns (AssetBreakdown memory breakdown);

    function getState() external view returns (RoycoKernelState memory);
}
