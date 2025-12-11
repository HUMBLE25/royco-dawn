// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TrancheDeploymentParams } from "../../libraries/Types.sol";
import { TrancheType } from "../../libraries/Types.sol";
import { BaseRoycoTranche } from "../BaseRoycoTranche.sol";

// TODO: ST and JT base asset can have different decimals
contract RoycoJT is BaseRoycoTranche {
    /// @notice Initializes the Royco junior tranche
    /// @param _jtParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the junior tranche
    /// @param _asset The underlying asset for the tranche
    /// @param _owner The initial owner of the tranche
    /// @param _pauser The initial pauser of the tranche
    /// @param _marketId The identifier of the Royco market this tranche is linked to
    function initialize(TrancheDeploymentParams calldata _jtParams, address _asset, address _owner, address _pauser, bytes32 _marketId) external initializer {
        // Initialize the Royco Junior Tranche
        __RoycoTranche_init(_jtParams, _asset, _owner, _pauser, _marketId);
    }

    /// @inheritdoc BaseRoycoTranche
    function TRANCHE_TYPE() public pure virtual override(BaseRoycoTranche) returns (TrancheType) {
        return TrancheType.JUNIOR;
    }
}
