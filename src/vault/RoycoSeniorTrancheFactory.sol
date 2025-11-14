// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BeaconProxy, IBeacon } from "../../lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import { RoycoSeniorTranche } from "./RoycoSeniorTranche.sol";

abstract contract RoycoSeniorTrancheFactory is IBeacon {
    // TODO: Setter
    address public roycoVaultImplementation;

    constructor(address _roycoVaultImplementation) {
        roycoVaultImplementation = _roycoVaultImplementation;
    }

    /// @inheritdoc IBeacon
    function implementation() external view virtual override returns (address) {
        return roycoVaultImplementation;
    }

    function _deployVault(
        string calldata _name,
        string calldata _symbol,
        address _owner,
        address _kernel,
        address _asset,
        address _feeClaimant,
        uint24 _yieldFeeBPS,
        address _jtVault,
        uint24 _jtTrancheCoverageFactorBPS,
        bytes calldata _kernelParams
    )
        internal
        returns (address vault)
    {
        // Deploy a new beacon proxy for the vault
        bytes memory initData = abi.encodeCall(
            RoycoSeniorTranche.initialize,
            (_name, _symbol, _owner, _kernel, _asset, _feeClaimant, _yieldFeeBPS, _jtVault, _jtTrancheCoverageFactorBPS, _kernelParams)
        );
        vault = address(new BeaconProxy(address(this), initData));
    }
}
