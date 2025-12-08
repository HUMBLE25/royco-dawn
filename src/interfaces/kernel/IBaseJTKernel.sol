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
 * @title IBaseKernel
 *
 */
interface IBaseKernel {
    function jtMaxDeposit(address _receiver) external view returns (uint256);
    function jtMaxWithdraw(address _owner) external view returns (uint256);
    function jtTotalAssets() external view returns (uint256);
    function jtDeposit(uint256 _assets, address _caller, address _receiver) external returns (uint256 fractionOfTotalAssetsAllocatedWAD);
    function jtWithdraw(
        uint256 _assets,
        address _caller,
        address _receiver
    )
        external
        returns (uint256 fractionOfTotalAssetsRedeemedWAD, uint256 assetsWithdrawn);
}
