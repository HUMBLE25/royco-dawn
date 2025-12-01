// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRoycoJuniorTranche, IRoycoTranche } from "../../interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { ExecutionModel, RoycoKernelLib } from "../../libraries/RoycoKernelLib.sol";
import { RoycoTrancheStorageLib } from "../../libraries/RoycoTrancheStorageLib.sol";
import { Action, TrancheDeploymentParams } from "../../libraries/Types.sol";
import { BaseRoycoTranche, ERC4626Upgradeable, IERC20, Math } from "../BaseRoycoTranche.sol";

// TODO: ST and JT base asset can have different decimals
contract RoycoJT is IRoycoJuniorTranche, BaseRoycoTranche {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Thrown when the caller is not the corresponding senior tranche
    error ONLY_SENIOR_TRANCHE();

    /**
     * @notice Initializes the Royco junior tranche
     * @param _jtParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the junior tranche
     * @param _asset The underlying asset for the tranche
     * @param _owner The initial owner of the tranche
     * @param _marketId The identifier of the Royco market this tranche is linked to
     * @param _coverageWAD The coverage condition in WAD format (1e18 = 100%)
     * @param _seniorTranche The address of the senior tranche corresponding to this junior tranche
     */
    function initialize(
        TrancheDeploymentParams calldata _jtParams,
        address _asset,
        address _owner,
        bytes32 _marketId,
        uint64 _coverageWAD,
        address _seniorTranche
    )
        external
        initializer
    {
        // Initialize the Royco Junior Tranche
        __RoycoTranche_init(_jtParams, _asset, _owner, _marketId, _coverageWAD, _seniorTranche);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Returns the junior tranche's effective total assets after factoring in any covered losses and yield distribution
    function totalAssets() public view override(BaseRoycoTranche) returns (uint256 jtEffectiveNAV) {
        (,,, jtEffectiveNAV) = _previewSyncTrancheNAVs();
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
        checkCoverage
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
        checkCoverage
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

    /// @inheritdoc IRoycoJuniorTranche
    function coverLosses(uint256 _assets, address _receiver) external returns (uint256 requestId) {
        // Ensure the caller is the senio
        require(msg.sender == RoycoTrancheStorageLib._getComplementTranche(), ONLY_SENIOR_TRANCHE());
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev No inherent tranche enforced cap on junior tranche deposits
    function _getTrancheDepositCapacity() internal pure override(BaseRoycoTranche) returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc BaseRoycoTranche
     * @notice Computes the assets that can be withdrawn from the junior tranche without violating the coverage condition
     * @dev Coverage condition: JT_NAV >= (JT_NAV + ST_NAV) * COV_%
     *      This is capped out when: JT_NAV == (JT_NAV + ST_NAV) * COV_%
     * @dev Solving for the max amount of assets we can withdraw from the junior tranche, x:
     *      (JT_NAV - x) = ((JT_NAV - x) + ST_NAV) * COV_%
     *      x = JT_NAV - ((ST_NAV * COV_%) / (100% - COV_%))
     */
    function _getTrancheWithdrawalCapacity() internal view override(BaseRoycoTranche) returns (uint256) {
        // Compute x, clipped to 0 to prevent underflow
        return Math.saturatingSub(_getJuniorTrancheNAV(), _computeMinJuniorTrancheNAV());
    }

    /// @inheritdoc BaseRoycoTranche
    function _getJuniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return _getSelfNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _getSeniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoTranche(RoycoTrancheStorageLib._getComplementTranche()).getNAV();
    }
}
