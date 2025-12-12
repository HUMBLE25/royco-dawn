// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TrancheDeploymentParams } from "../../libraries/Types.sol";
import { TrancheType } from "../../libraries/Types.sol";
import { RoycoVaultTranche } from "../RoycoVaultTranche.sol";

// TODO: ST and JT base asset can have different decimals
contract RoycoST is RoycoVaultTranche {
    /// @notice Initializes the Royco senior tranche
    /// @param _stParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the senior tranche
    /// @param _asset The underlying asset for the tranche
    /// @param _owner The initial owner of the tranche
    /// @param _pauser The initial pauser of the tranche
    /// @param _marketId The identifier of the Royco market this tranche is linked to
    function initialize(TrancheDeploymentParams calldata _stParams, address _asset, address _owner, address _pauser, bytes32 _marketId) external initializer {
        // Initialize the Royco Senior Tranche
        __RoycoTranche_init(_stParams, _asset, _owner, _pauser, _marketId);
    }

    /// @inheritdoc RoycoVaultTranche
    function TRANCHE_TYPE() public pure virtual override(RoycoVaultTranche) returns (TrancheType) {
        return TrancheType.SENIOR;
    }
}
