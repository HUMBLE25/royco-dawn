// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRoycoSeniorTranche, IRoycoTranche } from "../../interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { ExecutionModel, RoycoKernelLib } from "../../libraries/RoycoKernelLib.sol";
import { RoycoTrancheStorageLib } from "../../libraries/RoycoTrancheStorageLib.sol";
import { ActionType, TrancheDeploymentParams } from "../../libraries/Types.sol";
import { BaseRoycoTranche, ERC4626Upgradeable, IERC20, Math } from "../BaseRoycoTranche.sol";

// TODO: ST and JT base asset can have different decimals
contract RoycoJT is BaseRoycoTranche {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes the Royco junior tranche
     * @param _jtParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the junior tranche
     * @param _asset The underlying asset for the tranche
     * @param _owner The initial owner of the tranche
     * @param _coverageWAD The coverage ratio in WAD format (1e18 = 100%)
     * @param _seniorTranche The address of the senior tranche corresponding to this junior tranche
     */
    function initialize(
        TrancheDeploymentParams calldata _jtParams,
        address _asset,
        address _owner,
        uint64 _coverageWAD,
        address _seniorTranche
    )
        external
        initializer
    {
        // Initialize the Royco Junior Tranche
        __RoycoTranche_init(_jtParams, _asset, _owner, _coverageWAD, _seniorTranche);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Returns the junior tranche's effective total assets after factoring in any covered losses and yield distribution
    function totalAssets() public view override(BaseRoycoTranche) returns (uint256) {
        // TODO: Yield distribution and fee accrual
        // Get the NAV of the senior tranche and the total principal deployed into the investment
        uint256 stNAV = IRoycoTranche(RoycoTrancheStorageLib._getComplementTranche()).getNAV();
        uint256 stPrincipal = _getSeniorTranchePrincipal();

        // Junior tranche doesn't need to absorb any losses from senior if they are in profit
        uint256 jtNAV = _getJuniorTrancheNAV();
        if (stNAV >= stPrincipal) return jtNAV;

        // Senior tranche has incurred a loss
        // Calculate the loss relative to the principal
        uint256 stLoss = stPrincipal - stNAV;
        // Compute the coverage commitment provided by the junior tranche
        // Round up in favor of the senior tranche
        uint256 jtCoverageCommitment = stPrincipal.mulDiv(RoycoTrancheStorageLib._getCoverageWAD(), ConstantsLib.WAD, Math.Rounding.Ceil);
        // The loss absorbed by JT cannot exceed their coverage commitment amount
        uint256 jtLoss = Math.min(stLoss, jtCoverageCommitment);

        // Return the total assets held by the junior tranche after absorbing losses, clipped to 0
        return Math.saturatingSub(jtNAV, jtLoss);
    }

    /// @inheritdoc BaseRoycoTranche
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        override(BaseRoycoTranche)
        onlyCallerOrOperator(_controller)
        returns (uint256 shares)
    {
        // Assert that the assets being withdrawn by the user fall under the permissible limits
        uint256 maxWithdrawableAssets = maxWithdraw(_controller);
        require(_assets <= maxWithdrawableAssets, ERC4626ExceededMaxWithdraw(_controller, _assets, maxWithdrawableAssets));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, _assets, (shares = super.previewWithdraw(_assets)));

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        RoycoKernelLib._withdraw(RoycoTrancheStorageLib._getKernel(), asset(), _assets, _controller, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    function redeem(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        override(BaseRoycoTranche)
        onlyCallerOrOperator(_controller)
        returns (uint256 assets)
    {
        // Assert that the shares being redeeemed by the user fall under the permissible limits
        uint256 maxRedeemableShares = maxRedeem(_controller);
        require(_shares <= maxRedeemableShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxRedeemableShares));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, (assets = super.previewRedeem(_shares)), _shares);

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        RoycoKernelLib._withdraw(RoycoTrancheStorageLib._getKernel(), asset(), assets, _controller, _receiver);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev No inherent tranche enforced cap on junior tranche deposits
    function _getTrancheDepositCapacity() internal pure override(BaseRoycoTranche) returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc BaseRoycoTranche
     * @notice Computes the assets that can be withdrawn from the junior tranche without violating the coverage condition
     * @dev Coverage condition: JT_NAV >= (JT_NAV + ST_Principal) * Coverage_%
     *      This is capped out when: JT_NAV == (JT_NAV + ST_Principal) * Coverage_%
     * @dev Solving for the max amount of assets we can withdraw from the junior tranche, x:
     *      (JT_NAV - x) = ((JT_NAV - x) + ST_Principal) * Coverage_%
     *      x = JT_NAV - ((ST_Principal * Coverage_%) / (100% - Coverage_%))
     */
    function _getTrancheWithdrawalCapacity() internal view override(BaseRoycoTranche) returns (uint256) {
        uint256 minJuniorTrancheNAV = _getMinJuniorTrancheNAV();
        // Compute x, clipped to 0 to prevent underflow
        return Math.saturatingSub(_getJuniorTrancheNAV(), minJuniorTrancheNAV);
    }

    /// @inheritdoc BaseRoycoTranche
    function _getJuniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return RoycoKernelLib._getNAV(RoycoTrancheStorageLib._getKernel(), asset());
    }

    /// @inheritdoc BaseRoycoTranche
    function _getSeniorTranchePrincipal() internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoSeniorTranche(RoycoTrancheStorageLib._getComplementTranche()).getTotalPrincipalAssets();
    }
}
