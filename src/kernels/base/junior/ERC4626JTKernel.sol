// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.28;

// import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
// import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
// import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
// import { ExecutionModel, IRoycoKernel, RequestRedeemSharesBehavior } from "../../../interfaces/kernel/IRoycoKernel.sol";
// import { ZERO_TRANCHE_UNITS } from "../../../libraries/Constants.sol";
// import { AssetClaims } from "../../../libraries/Types.sol";
// import { NAV_UNIT, TRANCHE_UNIT, UnitsMathLib, toTrancheUnits, toUint256 } from "../../../libraries/Units.sol";
// import { UtilsLib } from "../../../libraries/UtilsLib.sol";
// import { ERC4626KernelStorageLib } from "../../../libraries/kernels/ERC4626KernelStorageLib.sol";
// import { Operation, RoycoKernel, TrancheType } from "../RoycoKernel.sol";

// abstract contract ERC4626JTKernel is RoycoKernel {
//     using SafeERC20 for IERC20;
//     using UnitsMathLib for TRANCHE_UNIT;

//     /// @inheritdoc IRoycoKernel
//     ExecutionModel public constant JT_INCREASE_NAV_EXECUTION_MODEL = ExecutionModel.SYNC;

//     /// @inheritdoc IRoycoKernel
//     ExecutionModel public constant JT_DECREASE_NAV_EXECUTION_MODEL = ExecutionModel.ASYNC;

//     /// @inheritdoc IRoycoKernel
//     RequestRedeemSharesBehavior public constant JT_REQUEST_REDEEM_SHARES_BEHAVIOR = RequestRedeemSharesBehavior.BURN_ON_REDEEM;

//     /// @notice Thrown when the ST base asset is different the the ERC4626 vault's base asset
//     error TRANCHE_AND_VAULT_ASSET_MISMATCH();

//     /**
//      * @notice Initializes a kernel where the senior tranche is deployed into an ERC4626 vault
//      * @dev Mandates that the base kernel state is already initialized
//      * @param _jtVault The address of the ERC4626 compliant vault
//      * @param _jtAsset The address of the base asset of the senior tranche
//      */
//     function __ERC4626_ST_Kernel_init_unchained(address _jtVault, address _jtAsset) internal onlyInitializing {
//         // Ensure that the ST base asset is identical to the ERC4626 vault's base asset
//         require(IERC4626(_jtVault).asset() == _stAsset, TRANCHE_AND_VAULT_ASSET_MISMATCH());

//         // Extend a one time max approval to the ERC4626 vault for the ST's base asset
//         IERC20(_jtAsset).forceApprove(address(_jtVault), type(uint256).max);

//         // Initialize the ERC4626 ST kernel storage
//         ERC4626KernelStorageLib.__ERC4626Kernel_init(_vault);
//     }
// }
