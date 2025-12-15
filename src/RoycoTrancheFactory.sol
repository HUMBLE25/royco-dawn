// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ERC1967Proxy } from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ExecutionModel, IRoycoKernel } from "./interfaces/kernel/IRoycoKernel.sol";
import { TrancheDeploymentParams } from "./libraries/Types.sol";
import { RoycoJT } from "./tranches/RoycoJT.sol";
import { RoycoST } from "./tranches/RoycoST.sol";

/// @title RoycoTrancheFactory
/// @notice Factory contract for deploying Royco tranches (ST and JT) and their associated kernel using ERC1967 proxies
/// @dev This factory deploys upgradeable tranche contracts using the UUPS proxy pattern
contract RoycoTrancheFactory {
    /// @notice Thrown when an invalid ST implementation address is provided
    error InvalidSTImplementation();
    /// @notice Thrown when an invalid JT implementation address is provided
    error InvalidJTImplementation();
    /// @notice Thrown when an invalid asset address is provided
    error InvalidAsset();
    /// @notice Thrown when an invalid owner address is provided
    error InvalidOwner();
    /// @notice Thrown when no kernel is provided
    error KernelRequired();

    /// @notice Emitted when a new market is deployed
    event MarketDeployed(
        address indexed seniorTranche,
        address indexed juniorTranche,
        address indexed kernel,
        bytes32 marketId,
        address seniorAsset,
        address juniorAsset,
        address owner
    );

    /// @notice The implementation address for RoycoST
    address public immutable ROYCO_ST_IMPLEMENTATION;
    /// @notice The implementation address for RoycoJT
    address public immutable ROYCO_JT_IMPLEMENTATION;

    /// @notice Initializes the factory with tranche implementation addresses
    constructor(address _roycoSTImplementation, address _roycoJTImplementation) {
        require(_roycoSTImplementation != address(0), InvalidSTImplementation());
        require(_roycoJTImplementation != address(0), InvalidJTImplementation());
        ROYCO_ST_IMPLEMENTATION = _roycoSTImplementation;
        ROYCO_JT_IMPLEMENTATION = _roycoJTImplementation;
    }

    /// @notice Deploys a new market with senior tranche, junior tranche, and kernel
    /// @param _seniorTrancheName The name of the senior tranchek
    /// @param _seniorTrancheSymbol The symbol of the senior tranche
    /// @param _juniorTrancheName The name of the junior tranche
    /// @param _juniorTrancheSymbol The symbol of the junior tranche
    /// @param _kernelImplementation The kernel implementation address
    /// @param _seniorAsset The underlying asset for the senior tranche
    /// @param _juniorAsset The underlying asset for the junior tranche
    /// @param _owner The initial owner of both tranches
    /// @param _pauser The initial pauser of both tranches
    /// @param _marketId The identifier of the Royco market
    /// @return seniorTranche The address of the deployed senior tranche proxy
    /// @return juniorTranche The address of the deployed junior tranche proxy
    function deployMarket(
        string memory _seniorTrancheName,
        string memory _seniorTrancheSymbol,
        string memory _juniorTrancheName,
        string memory _juniorTrancheSymbol,
        address _seniorAsset,
        address _juniorAsset,
        address _kernelImplementation,
        address _owner,
        address _pauser,
        bytes32 _marketId
    )
        external
        returns (address seniorTranche, address juniorTranche)
    {
        require(_seniorAsset != address(0), InvalidAsset());
        require(_juniorAsset != address(0), InvalidAsset());
        require(_owner != address(0), InvalidOwner());
        require(_kernelImplementation != address(0), KernelRequired());

        // Deploy senior tranche proxy first
        seniorTranche = _deployTranche(
            ROYCO_ST_IMPLEMENTATION,
            abi.encodeCall(
                RoycoST.initialize,
                (
                    TrancheDeploymentParams({ name: _seniorTrancheName, symbol: _seniorTrancheSymbol, kernel: _kernelImplementation }),
                    _seniorAsset,
                    _owner,
                    _pauser,
                    _marketId
                )
            )
        );

        // Deploy junior tranche proxy
        juniorTranche = _deployTranche(
            ROYCO_JT_IMPLEMENTATION,
            abi.encodeCall(
                RoycoJT.initialize,
                (
                    TrancheDeploymentParams({ name: _juniorTrancheName, symbol: _juniorTrancheSymbol, kernel: _kernelImplementation }),
                    _juniorAsset,
                    _owner,
                    _pauser,
                    _marketId
                )
            )
        );

        emit MarketDeployed(seniorTranche, juniorTranche, _kernelImplementation, _marketId, _seniorAsset, _juniorAsset, _owner);

        return (seniorTranche, juniorTranche);
    }

    /// @notice Deploys a tranche using ERC1967 proxy
    /// @param _implementation The implementation address
    /// @param _initData The initialization data
    /// @return proxy The deployed proxy address
    function _deployTranche(address _implementation, bytes memory _initData) internal returns (address proxy) {
        proxy = address(new ERC1967Proxy(_implementation, _initData));
    }
}
