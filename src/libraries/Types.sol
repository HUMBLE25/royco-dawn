// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

struct Market {
    uint64 coverageWAD;
    address seniorTranche;
    address juniorTranche;
    uint256 lastSeniorNAV;
    uint256 lastJuniorNAV;
    uint256 lastSeniorTotalAssets;
    uint256 lastJuniorTotalAssets;
}

/**
 * @notice Parameters required for Royco market creation
 * @custom:field owner - The owner of this market
 * @custom:field asset - The markets deposit and withdrawal asset for senior and junior tranches
 * @custom:field rewardFeeWAD - The percentage of the yield that is paid to the protocol (WAD = 100%)
 * @custom:field feeClaimant - The fee claimant for the reward fee
 * @custom:field rdm - The Reward Distribution Model (RDM) - Responsible for determing the yield split between junior and senior tranche
 * @custom:field coverageWAD - The percentage of the senior tranche that is always insured by the junior tranche (WAD = 100%)
 * @custom:field stParams - The deployment params for the senior tranche
 * @custom:field jtParams - The deployment params for the junior tranche
 */
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

/**
 * @custom:field name - The name of the tranche (should be prefixed with "Royco-ST" or "Royco-JT") share token
 * @custom:field symbol - The symbol of the tranche (should be prefixed with "ST" or "JT") share token
 * @custom:field kernel - The tranche kernel responsible for defining the execution model and logic of the tranche
 * @custom:field kernelInitCallData - ABI encoded parameters to intialize the tranche kernel
 */
struct TrancheDeploymentParams {
    string name;
    string symbol;
    address kernel;
    bytes kernelInitCallData;
}

/**
 * @title Action
 * @dev Defines the action being executed by the user
 * @custom:type DEPOSIT Depositing assets into the tranche
 * @custom:type WITHDRAW Withdrawing assets from the tranche
 */
enum Action {
    DEPOSIT,
    WITHDRAW
}

/**
 * @title TrancheType
 * @dev Defines the two types of Royco tranches deployed per market.
 * @custom:type JUNIOR The identifier for the junior tranche (first-loss capital)
 * @custom:type SENIOR The identifier for the senior tranche (second-loss capital)
 */
enum TrancheType {
    JUNIOR,
    SENIOR
}

library TypesLib {
    function Id(CreateMarketParams calldata _createMarketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode(_createMarketParams));
    }
}
