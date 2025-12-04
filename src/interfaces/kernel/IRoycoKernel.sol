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
 * @title IRoycoKernel
 *
 */
interface IRoycoBaseKernel {
    function getSTRawNAV() external view returns (uint256);
    function getJTRawNAV() external view returns (uint256);

    function getSTEffectiveNAV() external view returns (uint256);
    function getJTEffectiveNAV() external view returns (uint256);

    function syncTrancheNAVs() external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);

    function previewSyncTrancheNAVs() external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV);

    function stMaxDeposit(address _receiver) external view returns (uint256);
    function stMaxWithdraw(address _owner) external view returns (uint256);
    function stDeposit(uint256 _assets, address _caller, address _receiver) external;
    function stWithdraw(uint256 _assets, address _caller, address _receiver) external;

    function jtMaxDeposit(address _receiver) external view returns (uint256);
    function jtMaxWithdraw(address _owner) external view returns (uint256);
    function jtDeposit(uint256 _assets, address _caller, address _receiver) external;
    function jtWithdraw(uint256 _assets, address _caller, address _receiver) external;
}
