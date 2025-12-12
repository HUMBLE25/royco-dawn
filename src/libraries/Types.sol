// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice A struct representing a Royco market and its state
/// @custom:field seniorTranche - The market's senior tranche
/// @custom:field juniorTranche - The market's junior tranche
/// @custom:field rdm - The market's Reward Distribution Model (RDM), responsible for determining the allocation of the ST's yield between ST and JT
/// @custom:field coverageWAD - The expected minimum coverage provided by the junior tranche to the senior tranche at all times (scaled by WAD)
/// @custom:field lastSTRawNAV - The last recorded raw NAV (excluding any losses, coverage, and yield accrual) of the senior tranche
/// @custom:field lastJTRawNAV - The last recorded raw NAV (excluding any losses, coverage, and yield accrual) of the junior tranche
/// @custom:field lastSTEffectiveNAV - The last recorded effective NAV (including any losses, coverage, and yield accrual) of the senior tranche
/// @custom:field lastJTEffectiveNAV - The last recorded effective NAV (including any losses, coverage, and yield accrual) of the junior tranche
/// @custom:field twJTYieldShareAccruedWAD - The time-weighted junior tranche yield share (RDM output) since the last yield distribution
/// @custom:field lastAccrualTimestamp - The last time the time-weighted JT yield share accumulator was updated
/// @custom:field lastDistributionTimestamp - The last time a yield distribution occurred
struct Market {
    address seniorTranche;
    address juniorTranche;
    address rdm;
    uint64 coverageWAD;
    uint256 lastSTRawNAV;
    uint256 lastJTRawNAV;
    uint256 lastSTEffectiveNAV;
    uint256 lastJTEffectiveNAV;
    uint192 twJTYieldShareAccruedWAD;
    uint32 lastAccrualTimestamp;
    uint32 lastDistributionTimestamp;
}

/// @notice Parameters required for Royco market creation
/// @custom:field owner - The owner of this market
/// @custom:field asset - The markets deposit and withdrawal asset for senior and junior tranches
/// @custom:field rewardFeeWAD - The percentage of the yield that is paid to the protocol (WAD = 100%)
/// @custom:field feeClaimant - The fee claimant for the reward fee
/// @custom:field rdm - The Reward Distribution Model (RDM) - Responsible for determing the yield split between junior and senior tranche
/// @custom:field coverageWAD - The percentage of the senior tranche that is always insured by the junior tranche (WAD = 100%)
/// @custom:field stParams - The deployment params for the senior tranche
/// @custom:field jtParams - The deployment params for the junior tranche
struct CreateMarketParams {
    address owner;
    address asset;
    uint64 rewardFeeWAD;
    address feeClaimant;
    address rdm;
    uint64 coverageWAD;
    TrancheDeploymentParams stParams;
    TrancheDeploymentParams jtParams;
}

/// @custom:field name - The name of the tranche (should be prefixed with "Royco-ST" or "Royco-JT") share token
/// @custom:field symbol - The symbol of the tranche (should be prefixed with "ST" or "JT") share token
/// @custom:field kernel - The tranche kernel responsible for defining the execution model and logic of the tranche
struct TrancheDeploymentParams {
    string name;
    string symbol;
    address kernel;
}

/// @title Action
/// @dev Defines the action being executed by the user
/// @custom:type DEPOSIT Depositing assets into the tranche
/// @custom:type WITHDRAW Withdrawing assets from the tranche
enum Action {
    DEPOSIT,
    WITHDRAW
}

/// @title TrancheType
/// @dev Defines the two types of Royco tranches deployed per market.
/// @custom:type JUNIOR The identifier for the junior tranche (first-loss capital)
/// @custom:type SENIOR The identifier for the senior tranche (second-loss capital)
enum TrancheType {
    JUNIOR,
    SENIOR
}

/// @title RequestRedeemSharesBehavior
/// @dev Defines the behavior of the shares when a redeem request is made
/// @custom:type BURN_ON_REQUEST The shares are burned when calling requestRedeem
/// @custom:type BURN_ON_REDEEM The shares are burned when calling redeem
enum RequestRedeemSharesBehavior {
    BURN_ON_REQUEST,
    BURN_ON_REDEEM
}

/// @title ExecutionModel
/// @dev Defines the execution semantics for the deposit or withdrawal flow of a vault
/// @custom:type SYNC Refers to the flow being synchronous (the vault uses ERC4626 for this flow)
/// @custom:type ASYNC Refers to the flow being asynchronous (the vault uses ERC7540 for this flow)
enum ExecutionModel {
    SYNC,
    ASYNC
}

library TypesLib {
    function Id(CreateMarketParams calldata _createMarketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode(_createMarketParams));
    }
}
