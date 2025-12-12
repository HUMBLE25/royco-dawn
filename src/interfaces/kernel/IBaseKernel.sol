// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ExecutionModel, RequestRedeemSharesBehavior } from "../../libraries/Types.sol";

/**
 * @title IBaseKernel
 *
 */
interface IBaseKernel {
    function ST_REQUEST_REDEEM_SHARES_BEHAVIOR() external pure returns (RequestRedeemSharesBehavior);
    function JT_REQUEST_REDEEM_SHARES_BEHAVIOR() external pure returns (RequestRedeemSharesBehavior);

    function ST_DEPOSIT_EXECUTION_MODEL() external pure returns (ExecutionModel);
    function ST_WITHDRAWAL_EXECUTION_MODEL() external pure returns (ExecutionModel);

    function JT_DEPOSIT_EXECUTION_MODEL() external pure returns (ExecutionModel);
    function JT_WITHDRAWAL_EXECUTION_MODEL() external pure returns (ExecutionModel);

    function getSTRawNAV() external view returns (uint256);
    function getJTRawNAV() external view returns (uint256);

    function getSTEffectiveNAV() external view returns (uint256);
    function getJTEffectiveNAV() external view returns (uint256);

    function getSTTotalEffectiveAssets() external view returns (uint256);
    function getJTTotalEffectiveAssets() external view returns (uint256);

    function syncTrancheNAVs() external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);

    // function previewSyncTrancheNAVs() external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);

    // TODO: Assume that the following functions also enforce the invariants
    function stMaxDeposit(address _asset, address _receiver) external view returns (uint256);
    function stMaxWithdraw(address _asset, address _owner) external view returns (uint256);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function stDeposit(
        address _asset,
        uint256 _assets,
        address _caller,
        address _receiver
    )
        external
        returns (uint256 valueAllocated, uint256 effectiveNAVToMintAt);
    function stRedeem(address _asset, uint256 _shares, uint256 _totalShares, address _controller, address _receiver) external returns (uint256 assetsWithdrawn);

    function jtMaxDeposit(address _asset, address _receiver) external view returns (uint256);
    function jtMaxWithdraw(address _asset, address _owner) external view returns (uint256);

    // Assumes that the funds are transferred to the kernel before the deposit call is made
    function jtDeposit(
        address _asset,
        uint256 _assets,
        address _caller,
        address _receiver
    )
        external
        returns (uint256 valueAllocated, uint256 effectiveNAVToMintAt);
    function jtRedeem(address _asset, uint256 _shares, uint256 _totalShares, address _controller, address _receiver) external returns (uint256 assetsWithdrawn);
}
