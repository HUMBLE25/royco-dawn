// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title ExecutionModel
 * @dev Defines the execution semantics for the deposit or withdrawal flow of a vault
 * @custom:type SYNC Refers to the flow being synchronous (the vault uses ERC4626 for this flow)
 * @custom:type ASYNC Refers to the flow being asynchronous (the vault uses ERC7540 for this flow)
 */
enum ExecutionModel {
    SYNC,
    ASYNC
}

/**
 * @title IRoycoBaseKernel
 * @notice NAV refers to the total value of the tranche in terms of the asset being insured (say USD)
 * @notice Total Assets refers to the total value of the tranche in terms of the asset being deposited (say BTC)
 */
interface IRoycoBaseKernel {
    function getDepositExecutionModel() external view returns (ExecutionModel);
    function getWithdrawExecutionModel() external view returns (ExecutionModel);

    function getSTRawNAV() external view returns (uint256);
    function getJTRawNAV() external view returns (uint256);

    function getSTEffectiveNAV() external view returns (uint256);
    function getJTEffectiveNAV() external view returns (uint256);

    function getSTTotalEffectiveAssets() external view returns (uint256);
    function getJTTotalEffectiveAssets() external view returns (uint256);

    function syncTrancheNAVs() external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);

    function previewSyncTrancheNAVs() external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);

    // TODO: Assume that the following functions also enforce the invariants
    function stMaxDeposit(address _receiver) external view returns (uint256);
    function stMaxWithdraw(address _owner) external view returns (uint256);
    function stDeposit(uint256 _assets, address _caller, address _receiver) external returns (uint256 fractionOfTotalAssetsAllocatedWAD);
    function stWithdraw(uint256 _assets, address _caller, address _receiver) external returns (uint256 fractionOfTotalAssetsRedeemedWAD, uint256 assetsRedeemed);

    function jtMaxDeposit(address _receiver) external view returns (uint256);
    function jtMaxWithdraw(address _owner) external view returns (uint256);
    function jtDeposit(uint256 _assets, address _caller, address _receiver) external returns (uint256 fractionOfTotalAssetsAllocatedWAD);
    function jtWithdraw(uint256 _assets, address _caller, address _receiver) external returns (uint256 fractionOfTotalAssetsRedeemedWAD, uint256 assetsRedeemed);
}
