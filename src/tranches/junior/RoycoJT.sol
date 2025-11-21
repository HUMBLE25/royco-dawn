// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.28;

// import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// import { IRoycoJuniorTranche, IRoycoSeniorTranche, IRoycoTranche } from "../../interfaces/tranche/IRoycoTranche.sol";
// import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
// import { ExecutionModel, RoycoKernelLib } from "../../libraries/RoycoKernelLib.sol";
// import { RoycoTrancheStorageLib } from "../../libraries/RoycoTrancheStorageLib.sol";
// import { ActionType, TrancheDeploymentParams } from "../../libraries/Types.sol";
// import { BaseRoycoTranche, ERC4626Upgradeable, IERC20, Math } from "../BaseRoycoTranche.sol";

// // TODO: ST and JT base asset can have different decimals
// contract RoycoJT is BaseRoycoTranche, IRoycoJuniorTranche {
//     using Math for uint256;
//     using SafeERC20 for IERC20;

//     /**
//      * @notice Post-condition that enforces the coverage requirement for new senior capital
//      * @dev Coverage condition: JT_NAV >= (JT_NAV + ST_Principal) * Coverage_%
//      *      If this fails, junior capital is insufficient to meet the coverage requirement for the post-deposit senior principal
//      * @dev Failure Modes:
//      *      1. Synchronous:  Junior capital is insufficient because of too many senior deposits proportional to junior NAV
//      *      2. Asynchronous: Junior capital is insufficient because it incurred a loss proportionally greater than what senior capital did
//      *                       Theoretically, this should not happen since junior will be deployed into the RFR or the same opportunity as senior
//      */
//     // modifier checkCoverage() {
//     //     // Safety must be checked after all state changes have been applied
//     //     _;
//     //     uint256 jtNAV = _getJuniorTrancheNAV();
//     //     uint256 requiredCoverageAssets =
//     //         (jtNAV + RoycoTrancheStorageLib._getTotalPrincipalAssets()).mulDiv(RoycoTrancheStorageLib._getCoverageWAD(), ConstantsLib.WAD);
//     //     require(jtNAV >= requiredCoverageAssets, INSUFFICIENT_JUNIOR_TRANCHE_COVERAGE());
//     // }

//     /**
//      * @notice Initializes the Royco junior tranche
//      * @param _jtParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the junior tranche
//      * @param _asset The underlying asset for the tranche
//      * @param _owner The initial owner of the tranche
//      * @param _coverageWAD The coverage ratio in WAD format (1e18 = 100%)
//      * @param _seniorTranche The address of the senior tranche corresponding to this junior tranche
//      */
//     function initialize(
//         TrancheDeploymentParams calldata _jtParams,
//         address _asset,
//         address _owner,
//         uint64 _coverageWAD,
//         address _seniorTranche
//     )
//         external
//         initializer
//     {
//         // Initialize the Royco Junior Tranche
//         __RoycoTranche_init(_jtParams, _asset, _owner, _coverageWAD, _seniorTranche);
//     }

//     /// @inheritdoc IRoycoJuniorTranche
//     function getNAV() external view virtual override(IRoycoJuniorTranche) returns (uint256) {
//         return RoycoKernelLib._getNAV(RoycoTrancheStorageLib._getKernel(), asset());
//     }

//     /// @inheritdoc BaseRoycoTranche
//     /// @dev Returns the junior tranche's effective total assets after factoring in any covered losses and yield distribution
//     function totalAssets() public view override(BaseRoycoTranche) returns (uint256) { }

//     /// @inheritdoc BaseRoycoTranche
//     function withdraw(
//         uint256 _assets,
//         address _receiver,
//         address _controller
//     )
//         public
//         override(BaseRoycoTranche)
//         onlyCallerOrOperator(_controller)
//         returns (uint256 shares)
//     {
//         // Assert that the assets being withdrawn by the user fall under the permissible limits
//         uint256 maxWithdrawableAssets = maxWithdraw(_controller);
//         require(_assets <= maxWithdrawableAssets, ERC4626ExceededMaxWithdraw(_controller, _assets, maxWithdrawableAssets));

//         // Handle burning shares and principal accouting on withdrawal
//         _withdraw(msg.sender, _receiver, _controller, _assets, (shares = super.previewWithdraw(_assets)));

//         // Process the withdrawal from the underlying investment opportunity
//         // It is expected that the kernel transfers the assets directly to the receiver
//         RoycoKernelLib._withdraw(RoycoTrancheStorageLib._getKernel(), asset(), _assets, _controller, _receiver);
//     }

//     /// @inheritdoc BaseRoycoTranche
//     function redeem(
//         uint256 _shares,
//         address _receiver,
//         address _controller
//     )
//         public
//         override(BaseRoycoTranche)
//         onlyCallerOrOperator(_controller)
//         returns (uint256 assets)
//     {
//         // Assert that the shares being redeeemed by the user fall under the permissible limits
//         uint256 maxRedeemableShares = maxRedeem(_controller);
//         require(_shares <= maxRedeemableShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxRedeemableShares));

//         // Handle burning shares and principal accouting on withdrawal
//         _withdraw(msg.sender, _receiver, _controller, (assets = super.previewRedeem(_shares)), _shares);

//         // Process the withdrawal from the underlying investment opportunity
//         // It is expected that the kernel transfers the assets directly to the receiver
//         RoycoKernelLib._withdraw(RoycoTrancheStorageLib._getKernel(), asset(), assets, _controller, _receiver);
//     }
// }
