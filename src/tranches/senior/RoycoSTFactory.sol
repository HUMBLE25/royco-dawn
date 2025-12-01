// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BeaconProxy, IBeacon } from "../../../lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import { TrancheDeploymentParams } from "../../libraries/Types.sol";
import { RoycoST } from "./RoycoST.sol";

abstract contract RoycoSTFactory is IBeacon {
    /// @notice The implementation of Royco's Senior Tranche
    address public roycoSTImplementation;

    event SeniorTrancheImplementationSet(address roycoSTImplementation);

    constructor(address _roycoSTImplementation) {
        _setSTImplementation(_roycoSTImplementation);
    }

    /// @inheritdoc IBeacon
    function implementation() external view virtual override returns (address) {
        return roycoSTImplementation;
    }

    function _deploySeniorTranche(
        TrancheDeploymentParams calldata _stParams,
        address _asset,
        address _owner,
        bytes32 _marketId,
        uint64 _coverageWAD,
        address _juniorTranche
    )
        internal
        returns (address seniorTranche)
    {
        // Marshal the initialization parameters for the senior tranche deployment
        bytes memory initData = abi.encodeCall(RoycoST.initialize, (_stParams, _asset, _owner, _marketId, _coverageWAD, _juniorTranche));

        // Deploy a new beacon proxy for the senior tranche
        seniorTranche = address(new BeaconProxy(address(this), initData));
    }

    function _setSTImplementation(address _roycoSTImplementation) internal {
        roycoSTImplementation = _roycoSTImplementation;
        emit SeniorTrancheImplementationSet(_roycoSTImplementation);
    }
}
