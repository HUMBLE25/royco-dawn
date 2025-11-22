// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRoycoJuniorTranche, IRoycoSeniorTranche, IRoycoTranche } from "../../interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { ExecutionModel, RoycoKernelLib } from "../../libraries/RoycoKernelLib.sol";
import { RoycoTrancheStorageLib } from "../../libraries/RoycoTrancheStorageLib.sol";
import { ActionType, TrancheDeploymentParams } from "../../libraries/Types.sol";
import { BaseRoycoTranche, ERC4626Upgradeable, IERC20, Math } from "../BaseRoycoTranche.sol";

// TODO: ST and JT base asset can have different decimals
contract RoycoST is BaseRoycoTranche, IRoycoSeniorTranche {
    using Math for uint256;

    /**
     * @notice Initializes the Royco senior tranche
     * @param _stParams Deployment parameters including name, symbol, kernel, and kernel initialization data for the senior tranche
     * @param _asset The underlying asset for the tranche
     * @param _owner The initial owner of the tranche
     * @param _coverageWAD The coverage ratio in WAD format (1e18 = 100%)
     * @param _juniorTranche The address of the junior tranche corresponding to this senior tranche
     */
    function initialize(
        TrancheDeploymentParams calldata _stParams,
        address _asset,
        address _owner,
        uint64 _coverageWAD,
        address _juniorTranche
    )
        external
        initializer
    {
        // Initialize the Royco Senior Tranche
        __RoycoTranche_init(_stParams, _asset, _owner, _coverageWAD, _juniorTranche);
    }

    /// @inheritdoc IRoycoSeniorTranche
    function getTotalPrincipalAssets() external view override(IRoycoSeniorTranche) returns (uint256) {
        return _getSeniorTranchePrincipal();
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Returns the senior tranche's effective total assets after factoring in any covered losses and yield distribution
    function totalAssets() public view override(BaseRoycoTranche) returns (uint256) {
        // TODO: Yield distribution and fee accrual
        // Get the NAV of the senior tranche and the total principal deployed into the investment
        uint256 stAssets = RoycoKernelLib._getNAV(RoycoTrancheStorageLib._getKernel(), asset());
        uint256 stPrincipal = _getSeniorTranchePrincipal();

        // Senior tranche is whole without any coverage required from junior capital
        if (stAssets >= stPrincipal) return stAssets;

        // Senior tranche NAV has incurred a loss
        // Compute the assets expected as coverage for the senior tranche
        // Round in favor of the senior tranche
        uint256 expectedCoverageAssets = stPrincipal.mulDiv(RoycoTrancheStorageLib._getCoverageWAD(), ConstantsLib.WAD, Math.Rounding.Ceil);

        // Compute the actual amount of coverage provided by the junior tranche as the minimum of what they committed to insuring and their current NAV
        // This will always equal the expected coverage amount unless junior experiences losses large enough that its NAV falls below the required coverage budget
        uint256 actualCoverageAssets = Math.min(expectedCoverageAssets, _getJuniorTrancheNAV());

        // Compute the result of the senior tranche bucket in the loss waterfall:
        // Case 1: Senior tranche has suffered a loss that junior can absorb fully
        // The senior tranche principal is the effective NAV after partially or fully applying the coverage
        // Case 2: Senior tranche has suffered a loss greater than what junior can absorb
        // The actual assets controlled by the senior tranche in addition to all the coverage is the effective NAV for senior depositors
        return Math.min(stPrincipal, stAssets + actualCoverageAssets);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Post-checks the coverage condition, ensuring that the new senior capital isn't undercovered
    function deposit(uint256 _assets, address _receiver, address _controller) public override(BaseRoycoTranche) checkCoverage returns (uint256 shares) {
        return super.deposit(_assets, _receiver, _controller);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Post-checks the coverage condition, ensuring that the new senior capital isn't undercovered
    function mint(uint256 _shares, address _receiver, address _controller) public override(BaseRoycoTranche) checkCoverage returns (uint256 assets) {
        return super.mint(_shares, _receiver, _controller);
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
    /// @dev Increases the total principal deposited into the tranche
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override(BaseRoycoTranche) {
        // Handle depositing assets and/or minting shares
        super._deposit(_caller, _receiver, _assets, _shares);

        // Increase the tranche's total principal by the assets being deposited
        RoycoTrancheStorageLib._increaseTotalPrincipal(_assets);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev Decreases the total principal of assets deposited into the tranche
    /// @dev NOTE: Doesn't transfer assets to the receiver. This is the responsibility of the kernel.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares) internal override(BaseRoycoTranche) {
        // Decrease the tranche's total principal by the proportion of shares being withdrawn
        uint256 principalAssetsWithdrawn = _getSeniorTranchePrincipal().mulDiv(_shares, totalSupply(), Math.Rounding.Ceil);
        RoycoTrancheStorageLib._decreaseTotalPrincipal(principalAssetsWithdrawn);

        // Handle burning shares
        super._withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    /**
     * @inheritdoc BaseRoycoTranche
     * @notice Computes the assets that can be deposited into the senior tranche without violating the coverage condition
     * @dev Coverage condition: JT_NAV >= (JT_NAV + ST_Principal) * Coverage_%
     *      This is capped out when: JT_NAV == (JT_NAV + ST_Principal) * Coverage_%
     * @dev Solving for the max amount of assets we can deposit into the senior tranche, x:
     *      JT_NAV = (JT_NAV + (ST_Principal + x)) * Coverage_%
     *      x = (JT_NAV / Coverage_%) - JT_NAV - ST_Principal
     */
    function _getTrancheDepositCapacity() internal view override(BaseRoycoTranche) returns (uint256) {
        // Retrieve the junior tranche net asset value
        uint256 jtNAV = _getJuniorTrancheNAV();
        if (jtNAV == 0) return 0;

        // Compute the total assets currently covered by the junior tranche
        // Round down in favor of the senior tranche
        uint256 totalCoveredAssets = jtNAV.mulDiv(ConstantsLib.WAD, RoycoTrancheStorageLib._getCoverageWAD(), Math.Rounding.Floor);
        // Get the current principal assets of the senior tranche
        uint256 stPrincipalAssets = _getSeniorTranchePrincipal();

        // Compute x, clipped to 0 to prevent underflow
        return Math.saturatingSub(totalCoveredAssets, jtNAV).saturatingSub(stPrincipalAssets);
    }

    /// @inheritdoc BaseRoycoTranche
    /// @dev No inherent tranche enforced cap on senior tranche withdrawals
    function _getTrancheWithdrawalCapacity() internal pure override(BaseRoycoTranche) returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc BaseRoycoTranche
    function _getJuniorTrancheNAV() internal view override(BaseRoycoTranche) returns (uint256) {
        return IRoycoJuniorTranche(RoycoTrancheStorageLib._getComplementTranche()).getNAV();
    }

    /// @inheritdoc BaseRoycoTranche
    function _getSeniorTranchePrincipal() internal view override(BaseRoycoTranche) returns (uint256) {
        return RoycoTrancheStorageLib._getTotalPrincipalAssets();
    }
}
