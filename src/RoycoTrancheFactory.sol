// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ERC1967Proxy } from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ExecutionModel, IRoycoKernel } from "./interfaces/kernel/IRoycoKernel.sol";
import { TrancheDeploymentParams } from "./libraries/Types.sol";
import { RoycoJT } from "./tranches/junior/RoycoJT.sol";
import { RoycoST } from "./tranches/senior/RoycoST.sol";

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
    /// @notice Thrown when kernel addresses in ST and JT params don't match
    error KernelMismatch();
    /// @notice Thrown when the kernel has an invalid deposit execution model
    error InvalidDepositModel();
    /// @notice Thrown when the kernel has an invalid withdraw execution model
    error InvalidWithdrawModel();
    /// @notice Emitted when a new market is deployed

    event MarketDeployed(address indexed seniorTranche, address indexed juniorTranche, address indexed kernel, bytes32 marketId, address asset, address owner);

    /// @notice The implementation address for RoycoST
    address public immutable ROYCO_ST_IMPLEMENTATION;
    /// @notice The implementation address for RoycoJT
    address public immutable ROYCO_JT_IMPLEMENTATION;

    /// @notice Initializes the factory with tranche implementation addresses
    /// @param _roycoSTImplementation The implementation address for the senior tranche
    /// @param _roycoJTImplementation The implementation address for the junior tranche
    constructor(address _roycoSTImplementation, address _roycoJTImplementation) {
        require(_roycoSTImplementation != address(0), InvalidSTImplementation());
        require(_roycoJTImplementation != address(0), InvalidJTImplementation());
        ROYCO_ST_IMPLEMENTATION = _roycoSTImplementation;
        ROYCO_JT_IMPLEMENTATION = _roycoJTImplementation;
    }

    /// @notice Deploys a new market with senior tranche, junior tranche, and kernel
    /// @param _stParams Deployment parameters for the senior tranche
    /// @param _jtParams Deployment parameters for the junior tranche
    /// @param _kernelImplementation The kernel implementation address (if address(0), uses kernel from _stParams.kernel)
    /// @param _asset The underlying asset for both tranches
    /// @param _owner The initial owner of both tranches
    /// @param _pauser The initial pauser of both tranches
    /// @param _marketId The identifier of the Royco market
    /// @return seniorTranche The address of the deployed senior tranche proxy
    /// @return juniorTranche The address of the deployed junior tranche proxy
    /// @return kernel The address of the kernel (either deployed or existing)
    function deployMarket(
        TrancheDeploymentParams calldata _stParams,
        TrancheDeploymentParams calldata _jtParams,
        address _kernelImplementation,
        address _asset,
        address _owner,
        address _pauser,
        bytes32 _marketId
    )
        external
        returns (address seniorTranche, address juniorTranche, address kernel)
    {
        require(_asset != address(0), InvalidAsset());
        require(_owner != address(0), InvalidOwner());
        require(_stParams.kernel != address(0) || _kernelImplementation != address(0), KernelRequired());

        // Deploy or use existing kernel
        if (_kernelImplementation != address(0)) {
            // Deploy new kernel implementation
            kernel = _deployKernel(_kernelImplementation);
        } else {
            // Use existing kernel from params
            kernel = _stParams.kernel;
            require(kernel == _jtParams.kernel, KernelMismatch());
        }

        // Verify kernel implements IRoycoKernel by checking it returns valid execution models
        // This will revert if the kernel doesn't implement the interface
        ExecutionModel depositModel = IRoycoKernel(kernel).ST_DEPOSIT_EXECUTION_MODEL();
        ExecutionModel withdrawModel = IRoycoKernel(kernel).ST_WITHDRAWAL_EXECUTION_MODEL();
        require(depositModel == ExecutionModel.SYNC || depositModel == ExecutionModel.ASYNC, InvalidDepositModel());
        require(withdrawModel == ExecutionModel.SYNC || withdrawModel == ExecutionModel.ASYNC, InvalidWithdrawModel());

        // Update params with the actual kernel address
        TrancheDeploymentParams memory stParams = _stParams;
        TrancheDeploymentParams memory jtParams = _jtParams;
        stParams.kernel = kernel;
        jtParams.kernel = kernel;

        // Deploy senior tranche proxy first
        seniorTranche = _deployTranche(ROYCO_ST_IMPLEMENTATION, abi.encodeCall(RoycoST.initialize, (stParams, _asset, _owner, _pauser, _marketId)));

        // Deploy junior tranche proxy
        juniorTranche = _deployTranche(ROYCO_JT_IMPLEMENTATION, abi.encodeCall(RoycoJT.initialize, (jtParams, _asset, _owner, _pauser, _marketId)));

        emit MarketDeployed(seniorTranche, juniorTranche, kernel, _marketId, _asset, _owner);

        return (seniorTranche, juniorTranche, kernel);
    }

    /// @notice Deploys a kernel implementation
    /// @param _kernelImplementation The kernel implementation contract address
    /// @return kernel The deployed kernel address
    /// @dev If the kernel is a regular contract (not a proxy), this returns the implementation address
    /// @dev If the kernel needs to be deployed as a proxy, override this function to deploy an ERC1967Proxy
    function _deployKernel(address _kernelImplementation) internal returns (address kernel) {
        // TODO
    }

    /// @notice Deploys a tranche using ERC1967 proxy
    /// @param _implementation The implementation address
    /// @param _initData The initialization data
    /// @return proxy The deployed proxy address
    function _deployTranche(address _implementation, bytes memory _initData) internal returns (address proxy) {
        proxy = address(new ERC1967Proxy(_implementation, _initData));
    }
}
