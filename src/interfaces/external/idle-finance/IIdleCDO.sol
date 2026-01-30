// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title Idle CDO interface
/// @author Idle Labs Inc.
/// @notice External interface for Idle CDO (Collateralized Debt Obligation) tranche operations
interface IIdleCDO {
    /// @notice Address of the AA (senior) tranche token contract
    /// @return Address of the AA tranche token
    function AATranche() external view returns (address);

    /// @notice Address of the BB (junior) tranche token contract
    /// @return Address of the BB tranche token
    function BBTranche() external view returns (address);

    /// @notice Address for stkIDLE gating for AA tranche. addr(0) = inactive, addr(1) = active
    /// @return Staking contract address for AA tranche
    function AAStaking() external view returns (address);

    /// @notice Address for stkIDLE gating for BB tranche. addr(0) = inactive, addr(1) = active
    /// @return Staking contract address for BB tranche
    function BBStaking() external view returns (address);

    /// @notice Address of the strategy used to lend funds
    /// @return Strategy contract address
    function strategy() external view returns (address);

    /// @notice Address of the strategy token representing the position in the lending provider
    /// @return Strategy token address
    function strategyToken() external view returns (address);

    /// @notice Underlying token (e.g. DAI)
    /// @return Underlying token address
    function token() external view returns (address);

    /// @notice Address that can call harvest and lend pool assets
    /// @return Rebalancer address
    function rebalancer() external view returns (address);

    /// @notice Contract owner
    /// @return Owner address
    function owner() external view returns (address);

    /// @notice Whether deposits are paused
    /// @return True if paused
    function paused() external view returns (bool);

    /// @notice If true, deposits go directly into the strategy
    /// @return True if direct deposit is enabled
    function directDeposit() external view returns (bool);

    /// @notice Whether AA tranche withdrawals are allowed (e.g. when paused)
    /// @return True if AA withdrawals are allowed
    function allowAAWithdraw() external view returns (bool);

    /// @notice Whether BB tranche withdrawals are allowed (e.g. when paused)
    /// @return True if BB withdrawals are allowed
    function allowBBWithdraw() external view returns (bool);

    /// @notice Fee amount (relative to FULL_ALLOC, e.g. 15000 = 15%)
    /// @return Fee in basis points (FULL_ALLOC = 100%)
    function fee() external view returns (uint256);

    /// @notice TVL limit in underlying value. 0 means unlimited
    /// @return Limit in underlying token units
    function limit() external view returns (uint256);

    /// @notice Unclaimed fees for feeReceiver
    /// @return Unclaimed fees in underlying units
    function unclaimedFees() external view returns (uint256);

    /// @notice Actual APR for a tranche given current ratio between AA and BB
    /// @param _tranche Tranche address (AATranche or BBTranche)
    /// @return APR for the tranche
    function getApr(address _tranche) external view returns (uint256);

    /// @notice Current net TVL in `token` terms. Unclaimed rewards and unclaimedFees are not counted
    /// @dev Harvested rewards counted only after releaseBlocksPeriod
    /// @return Contract value in underlying token units
    function getContractValue() external view returns (uint256);

    /// @notice APR split ratio for AA tranches (relative to FULL_ALLOC, e.g. 10000 = 10% to AA, 90% to BB)
    /// @return APR split ratio (FULL_ALLOC = 100%)
    function trancheAPRSplitRatio() external view returns (uint256);

    /// @notice Current AA tranche ratio (in underlying value) considering all interest
    /// @dev Uses virtual balance for ratio including accrued interest since last deposit/withdraw/harvest
    /// @return AA ratio (FULL_ALLOC = 100%)
    function getCurrentAARatio() external view returns (uint256);

    /// @notice Tranche price in underlyings at last interaction (excludes interest since last interaction)
    /// @param _tranche Tranche address
    /// @return Price in underlying units per tranche token (18 decimals)
    function tranchePrice(address _tranche) external view returns (uint256);

    /// @notice Tranche price including interest/loss not yet split (since last deposit/withdraw/harvest)
    /// @param _tranche Tranche address
    /// @return Virtual price in underlying units per tranche token (18 decimals)
    function virtualPrice(address _tranche) external view returns (uint256);

    /// @notice [DEPRECATED] Tokens used to incentivize the idle tranche ideal ratio
    /// @return Array of incentive token addresses
    function getIncentiveTokens() external view returns (address[] memory);

    /// @notice Set unlent balance percentage (relative to FULL_ALLOC)
    /// @param _unlentPerc New unlent percentage
    function setUnlentPerc(uint256 _unlentPerc) external;

    /// @notice Deposit underlyings into AA tranche
    /// @dev Caller must approve this contract to spend `_amount` of token. Pausable.
    /// @param _amount Amount of token to deposit
    /// @return AA tranche tokens minted
    function depositAA(uint256 _amount) external returns (uint256);

    /// @notice Deposit underlyings into BB tranche
    /// @dev Caller must approve this contract to spend `_amount` of token. Pausable.
    /// @param _amount Amount of token to deposit
    /// @return BB tranche tokens minted
    function depositBB(uint256 _amount) external returns (uint256);

    /// @notice Burn AA tranche tokens and redeem underlyings
    /// @param _amount Amount of AA tranche tokens to burn
    /// @return Underlying tokens redeemed
    function withdrawAA(uint256 _amount) external returns (uint256);

    /// @notice Burn BB tranche tokens and redeem underlyings
    /// @param _amount Amount of BB tranche tokens to burn
    /// @return Underlying tokens redeemed
    function withdrawBB(uint256 _amount) external returns (uint256);

    /// @notice Pause deposits and (by default) prevent withdrawals for all tranches
    /// @dev Callable by owner or guardian
    function emergencyShutdown() external;

    /// @notice Set the guardian (can pause/unpause and call emergencyShutdown)
    /// @param _guardian New guardian address
    function setGuardian(address _guardian) external;

    /// @notice Lend user funds via strategy: redeem rewards, sell for underlyings, update accounting, deposit fees, then deposit in strategy
    /// @dev Callable only by rebalancer or owner
    /// @param _skipFlags [0] skip reward redemption, [1] skip incentives update (deprecated), [2] skip fee deposit, [3] skip all
    /// @param _skipReward Flags to skip selling specific rewards. Length = getRewardTokens().length
    /// @param _minAmount Min amounts for uniswap trades
    /// @param _sellAmounts Amounts of reward tokens to sell. 0 = swap full contract balance
    /// @param _extraData Bytes for redeemRewards and paths for swaps
    /// @return _res [0] soldAmounts, [1] swappedAmounts, [2] redeemedRewards
    function harvest(
        bool[] calldata _skipFlags,
        bool[] calldata _skipReward,
        uint256[] calldata _minAmount,
        uint256[] calldata _sellAmounts,
        bytes[] calldata _extraData
    )
        external
        returns (uint256[][] memory _res);
}
