// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from "../../../lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import { ERC20Upgradeable } from "../../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata,
    IERC4626,
    Math
} from "../../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC7540 } from "../../interfaces/IERC7540.sol";
import { IERC7575 } from "../../interfaces/IERC7575.sol";
import { IERC165, IERC7887 } from "../../interfaces/IERC7887.sol";
import { IRoycoTranche } from "../../interfaces/IRoycoTranche.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { ExecutionModel, RoycoKernelLib } from "../../libraries/RoycoKernelLib.sol";
import { RoycoSTStorageLib } from "../../libraries/RoycoSTStorageLib.sol";
import { ActionType, TrancheDeploymentParams } from "../../libraries/Types.sol";

contract RoycoST is IRoycoTranche, Ownable2StepUpgradeable, ERC4626Upgradeable, IERC7540, IERC7575, IERC7887 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    error DISABLED();
    error INVALID_CALLER();
    error INSUFFICIENT_JUNIOR_TRANCHE_COVERAGE();

    modifier executionIsSync(ActionType _actionType) {
        require(
            (_actionType == ActionType.DEPOSIT ? RoycoSTStorageLib._getDepositExecutionModel() : RoycoSTStorageLib._getWithdrawalExecutionModel())
                == ExecutionModel.SYNC,
            DISABLED()
        );
        _;
    }

    modifier onlySelfOrOperator(address _self) {
        require(msg.sender == _self || RoycoSTStorageLib._isOperator(_self, msg.sender), INVALID_CALLER());
        _;
    }

    modifier checkCoverageInvariant() {
        // Invariant must be post-checked, after all state changes have been applied
        _;
        // TODO: Might be redundant because maxDeposit and maxMint accounts for this invariant check
        /// @dev Invariant: JT_NAV >= (JT_NAV + ST_Principal) * Coverage_%
        /// @dev This invariant can be asynchronously violated if the junior tranche suffers losses
        uint256 jtNAV = RoycoSTStorageLib._getJuniorTranche().getNAV();
        uint256 requiredCoverageAssets = (jtNAV + RoycoSTStorageLib._getTotalPrincipalAssets()).mulDiv(RoycoSTStorageLib._getCoverageWAD(), ConstantsLib.WAD);
        require(jtNAV >= requiredCoverageAssets, INSUFFICIENT_JUNIOR_TRANCHE_COVERAGE());
    }

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
        // Initialize the parent contracts
        __ERC20_init_unchained(_stParams.name, _stParams.symbol);
        __ERC4626_init_unchained(IERC20(_asset));
        __Ownable_init_unchained(_owner);

        // Calculate the vault's decimal offset (curb inflation attacks)
        uint8 underlyingAssetDecimals = IERC20Metadata(_asset).decimals();
        uint8 decimalsOffset = underlyingAssetDecimals >= 18 ? 0 : (18 - underlyingAssetDecimals);

        // Initialize the senior tranche state
        RoycoSTStorageLib.__RoycoST_init(msg.sender, _stParams.kernel, _coverageWAD, _juniorTranche, decimalsOffset);

        // Initialize the kernel's state
        RoycoKernelLib.__Kernel_init(RoycoSTStorageLib._getKernel(), _stParams.kernelInitParams);
    }

    // =============================
    // Core ERC4626 deposit and withdrawal functions
    // =============================

    /// @inheritdoc IERC4626
    function deposit(uint256 _assets, address _receiver) public override(ERC4626Upgradeable) returns (uint256) {
        return deposit(_assets, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    function deposit(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        override(IERC7540)
        onlySelfOrOperator(_controller)
        checkCoverageInvariant
        returns (uint256 shares)
    {
        // Assert that the user's deposited assets fall under the max limit
        uint256 maxDepositableAssets = maxDeposit(_receiver);
        require(_assets <= maxDepositableAssets, ERC4626ExceededMaxDeposit(_receiver, _assets, maxDepositableAssets));

        // Handle depositing assets and minting shares
        _deposit(msg.sender, _receiver, _assets, (shares = super.previewDeposit(_assets)));

        // Process the deposit into the underlying investment opportunity by calling the kernel
        RoycoKernelLib._deposit(RoycoSTStorageLib._getKernel(), asset(), _assets, _controller);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 _shares, address _receiver) public override(ERC4626Upgradeable) returns (uint256) {
        return mint(_shares, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    function mint(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        override(IERC7540)
        onlySelfOrOperator(_controller)
        checkCoverageInvariant
        returns (uint256 assets)
    {
        // Assert that the shares minted to the user fall under the max limit
        uint256 maxMintableShares = maxMint(_receiver);
        require(_shares <= maxMintableShares, ERC4626ExceededMaxMint(_receiver, _shares, maxMintableShares));

        // Handle depositing assets and minting shares
        _deposit(msg.sender, _receiver, (assets = super.previewMint(_shares)), _shares);

        // Process the deposit for the underlying investment opportunity by calling the kernel
        RoycoKernelLib._deposit(RoycoSTStorageLib._getKernel(), asset(), assets, _controller);
    }

    /// @inheritdoc IERC7540
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        override(ERC4626Upgradeable, IERC7540)
        onlySelfOrOperator(_controller)
        returns (uint256 shares)
    {
        // Assert that the assets being withdrawn by the user fall under the permissible limits
        uint256 maxWithdrawableAssets = maxWithdraw(_controller);
        require(_assets <= maxWithdrawableAssets, ERC4626ExceededMaxWithdraw(_controller, _assets, maxWithdrawableAssets));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, _assets, (shares = super.previewWithdraw(_assets)));

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        RoycoKernelLib._withdraw(RoycoSTStorageLib._getKernel(), asset(), _assets, _controller, _receiver);
    }

    /// @inheritdoc IERC7540
    function redeem(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        override(ERC4626Upgradeable, IERC7540)
        onlySelfOrOperator(_controller)
        returns (uint256 assets)
    {
        // Assert that the shares being redeeemed by the user fall under the permissible limits
        uint256 maxRedeemableShares = maxRedeem(_controller);
        require(_shares <= maxRedeemableShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxRedeemableShares));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, (assets = super.previewRedeem(_shares)), _shares);

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        RoycoKernelLib._withdraw(RoycoSTStorageLib._getKernel(), asset(), assets, _controller, _receiver);
    }

    // =============================
    // ERC7540 Asynchronous flow functions
    // =============================

    /// @inheritdoc IERC7540
    function isOperator(address _controller, address _operator) external view override(IERC7540) returns (bool) {
        return RoycoSTStorageLib._isOperator(_controller, _operator);
    }

    /// @inheritdoc IERC7540
    function setOperator(address _operator, bool _approved) external override(IERC7540) returns (bool) {
        // Set the operator's approval status for the caller
        RoycoSTStorageLib._setOperator(msg.sender, _operator, _approved);
        emit OperatorSet(msg.sender, _operator, _approved);

        // Must return true as per ERC7540
        return true;
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function requestDeposit(
        uint256 _assets,
        address _controller,
        address _owner
    )
        external
        override(IERC7540)
        onlySelfOrOperator(_owner)
        returns (uint256 requestId)
    {
        // Transfer the assets from the owner to the tranche
        /// @dev NOTE: These assets must not be counted in the NAV (total assets). Enforced by the kernel.
        _transferIn(_owner, _assets);

        // Queue the deposit request and get the request ID from the kernel
        requestId = RoycoKernelLib._requestDeposit(RoycoSTStorageLib._getKernel(), _assets, _controller);

        emit DepositRequest(_controller, _owner, requestId, msg.sender, _assets);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function pendingDepositRequest(uint256 _requestId, address _controller) external override(IERC7540) returns (uint256) {
        return RoycoKernelLib._pendingDepositRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function claimableDepositRequest(uint256 _requestId, address _controller) external override(IERC7540) returns (uint256) {
        return RoycoKernelLib._claimableDepositRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function requestRedeem(uint256 _shares, address _controller, address _owner) external override(IERC7540) returns (uint256 requestId) {
        // Spend the caller's share allowance if the caller isn't the owner or an approved operator
        if (msg.sender != _owner && !RoycoSTStorageLib._isOperator(_owner, msg.sender)) _spendAllowance(_owner, msg.sender, _shares);
        // Transfer and lock the requested shares being redeemed from the owner to the tranche
        // NOTE: We must not burn the shares so that total supply remains unchanged when calculating the principal to decrease on redemption
        _transfer(_owner, address(this), _shares);

        // Calculate the assets to redeem
        uint256 _assets = super.previewRedeem(_shares);

        // Queue the redemption request and get the request ID from the kernel
        requestId = RoycoKernelLib._requestRedeem(RoycoSTStorageLib._getKernel(), _assets, _shares, _controller);

        emit RedeemRequest(_controller, _owner, requestId, msg.sender, _shares);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function pendingRedeemRequest(uint256 _requestId, address _controller) external override(IERC7540) returns (uint256 pendingShares) {
        return RoycoKernelLib._pendingRedeemRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function claimableRedeemRequest(uint256 _requestId, address _controller) external override(IERC7540) returns (uint256 claimableShares) {
        return RoycoKernelLib._claimableRedeemRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    // =============================
    // ERC-7887 Cancelation Functions
    // =============================

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function cancelDepositRequest(uint256 _requestId, address _controller) external override(IERC7887) onlySelfOrOperator(_controller) {
        // Delegate call to kernel to handle deposit cancellation
        RoycoKernelLib._cancelDepositRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);

        emit CancelDepositRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function pendingCancelDepositRequest(uint256 _requestId, address _controller) external override(IERC7887) returns (bool isPending) {
        return RoycoKernelLib._pendingCancelDepositRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function claimableCancelDepositRequest(uint256 _requestId, address _controller) external override(IERC7887) returns (uint256 assets) {
        return RoycoKernelLib._claimableCancelDepositRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function claimCancelDepositRequest(
        uint256 _requestId,
        address _receiver,
        address _controller
    )
        external
        override(IERC7887)
        onlySelfOrOperator(_controller)
    {
        // Get the claimable amount before claiming
        uint256 assets = RoycoKernelLib._claimableCancelDepositRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);

        // Transfer cancelled deposit assets to receiver
        _transferOut(_receiver, assets);

        emit CancelDepositClaim(_controller, _receiver, _requestId, msg.sender, assets);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function cancelRedeemRequest(uint256 _requestId, address _controller) external override(IERC7887) onlySelfOrOperator(_controller) {
        // Delegate call to kernel to handle redeem cancellation
        RoycoKernelLib._cancelRedeemRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);

        emit CancelRedeemRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function pendingCancelRedeemRequest(uint256 _requestId, address _controller) external override(IERC7887) returns (bool isPending) {
        return RoycoKernelLib._pendingCancelRedeemRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function claimableCancelRedeemRequest(uint256 _requestId, address _controller) external override(IERC7887) returns (uint256 shares) {
        return RoycoKernelLib._claimableCancelRedeemRequest(RoycoSTStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function claimCancelRedeemRequest(uint256 _requestId, address _receiver, address _owner) external override(IERC7887) onlySelfOrOperator(_owner) {
        // Get the claimable amount before claiming
        uint256 shares = RoycoKernelLib._claimableCancelRedeemRequest(RoycoSTStorageLib._getKernel(), _requestId, _owner);

        // Transfer the previously locked shares (on request) to the receiver
        _transfer(address(this), _receiver, shares);

        emit CancelRedeemClaim(_owner, _receiver, _requestId, msg.sender, shares);
    }

    // =============================
    // Core ERC4626 view functions
    // =============================

    function getNAV() external view override(IRoycoTranche) returns (uint256) {
        return RoycoKernelLib._getNAV(RoycoSTStorageLib._getKernel(), asset());
    }

    /// @inheritdoc IERC4626
    /// @dev Returns the senior tranche's effective total assets after factoring in losses covered by the junior tranche
    function totalAssets() public view override(ERC4626Upgradeable) returns (uint256) {
        // TODO: Yield distribution and fee accrual
        // Get the NAV of the senior tranche and the total principal deployed into the investment
        uint256 stAssets = RoycoKernelLib._getNAV(RoycoSTStorageLib._getKernel(), asset());
        uint256 stPrincipal = RoycoSTStorageLib._getTotalPrincipalAssets();

        // Senior tranche is completely whole, without any coverage required from junior capital
        if (stAssets >= stPrincipal) return stAssets;

        // Senior tranche NAV has incurred a loss
        // Compute the assets required as coverage for the senior tranche
        // Round in favor of the senior tranche
        uint256 expectedCoverageAssets = stPrincipal.mulDiv(RoycoSTStorageLib._getCoverageWAD(), ConstantsLib.WAD, Math.Rounding.Ceil);

        // Compute the actual amount of coverage provided by the junior tranche as the minimum of what they committed to insuring and their current NAV
        // This will equal the expected coverage amount except when junior experiences losses large enough that its NAV falls below the required coverage budget
        // Given the market's invariant for new deposits and withdrawals, This can only happen if junior’s losses are proportionally greater than senior’s losses
        uint256 actualCoverageAssets = Math.min(expectedCoverageAssets, RoycoSTStorageLib._getJuniorTranche().getNAV());

        // Compute the result of the senior tranche bucket in the loss waterfall:
        // Case 1: Senior tranche has suffered a loss that junior can absorb fully
        // The senior tranche principal is the effective NAV after partially or fully applying the coverage
        // Case 2: Senior tranche has suffered a loss greater than what junior can absorb
        // The actual assets controlled by the senior tranche in addition to all the coverage is the effective NAV
        return Math.min(stPrincipal, stAssets + actualCoverageAssets);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address _receiver) public view override(ERC4626Upgradeable) returns (uint256) {
        // Return the minimum of the asset capacity of the underlying investment opportunity and the senior tranche (to satisfy the coverage invariant)
        return Math.min(RoycoKernelLib._maxDeposit(RoycoSTStorageLib._getKernel(), msg.sender, _receiver, asset()), _computeSTDepositCapacity());
    }

    /// @inheritdoc IERC4626
    function maxMint(address _receiver) public view override(ERC4626Upgradeable) returns (uint256) {
        // Get the max assets depositable
        // Preview deposit will handle computing the maximum mintable shares
        return super.previewDeposit(maxDeposit(_receiver));
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address _owner) public view override(ERC4626Upgradeable) returns (uint256) {
        // Return the minimum of the maximum globally withdrawable assets and the assets held by the owner
        // Preview redeem will handle computing the max assets withdrawable by the owner
        return Math.min(RoycoKernelLib._maxWithdraw(RoycoSTStorageLib._getKernel(), msg.sender, _owner, asset()), super.previewRedeem(balanceOf(_owner)));
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address _owner) public view override(ERC4626Upgradeable) returns (uint256) {
        // Get the maximum globally withdrawable assets
        uint256 maxAssetsWithdrawable = RoycoKernelLib._maxWithdraw(RoycoSTStorageLib._getKernel(), msg.sender, _owner, asset());
        // Return the minimum of the shares equating to the maximum globally withdrawable assets and the shares held by the owner
        return Math.min(super.previewWithdraw(maxAssetsWithdrawable), balanceOf(_owner));
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewDeposit(uint256 _assets) public view override(ERC4626Upgradeable) executionIsSync(ActionType.DEPOSIT) returns (uint256) {
        return super.previewDeposit(_assets);
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewMint(uint256 _shares) public view override(ERC4626Upgradeable) executionIsSync(ActionType.DEPOSIT) returns (uint256) {
        return super.previewMint(_shares);
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewWithdraw(uint256 _assets) public view override(ERC4626Upgradeable) executionIsSync(ActionType.WITHDRAWAL) returns (uint256) {
        return super.previewWithdraw(_assets);
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewRedeem(uint256 _shares) public view override(ERC4626Upgradeable) executionIsSync(ActionType.WITHDRAWAL) returns (uint256) {
        return super.previewRedeem(_shares);
    }

    /// @inheritdoc IERC7575
    function share() external view override(IERC7575) returns (address) {
        return address(this);
    }

    /// @inheritdoc IERC7575
    function vault(address _asset) external view override(IERC7575) returns (address) {
        return _asset == asset() ? address(this) : address(0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public pure override(IERC165) returns (bool) {
        return _interfaceId == this.supportsInterface.selector || _interfaceId == type(IERC4626).interfaceId || _interfaceId == type(IERC7540).interfaceId
            || _interfaceId == type(IERC7887).interfaceId;
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Increases the total principal deposited into the tranche
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override(ERC4626Upgradeable) {
        // If deposits are synchronous, transfer the assets to the tranche and mint the shares
        if (RoycoSTStorageLib._getDepositExecutionModel() == ExecutionModel.SYNC) super._deposit(_caller, _receiver, _assets, _shares);
        // If deposits are asynchronous, only mint shares since assets were transfered in on the request
        else _mint(_receiver, _shares);

        // Increase the tranche's total principal by the assets being deposited
        RoycoSTStorageLib._increaseTotalPrincipal(_assets);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Decreases the total principal of assets deposited into the tranche
    /// @dev NOTE: Doesn't transfer assets to the receiver. This is the responsibility of the kernel.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares) internal override(ERC4626Upgradeable) {
        // Decrease the tranche's total principal by the proportion of shares being withdrawn
        uint256 principalAssetsWithdrawn = RoycoSTStorageLib._getTotalPrincipalAssets().mulDiv(_shares, totalSupply(), Math.Rounding.Ceil);
        RoycoSTStorageLib._decreaseTotalPrincipal(principalAssetsWithdrawn);

        // If withdrawals are synchronous, burn the shares from the owner
        if (RoycoSTStorageLib._getWithdrawalExecutionModel() == ExecutionModel.SYNC) {
            // Spend the caller's share allowance if the caller isn't the owner
            if (_caller != _owner) _spendAllowance(_owner, _caller, _shares);
            // Burn the shares being redeemed from the owner
            _burn(_owner, _shares);
        } else {
            // If withdrawals are asynchronous, burn the shares that were locked in the tranche on requesting the redemption
            _burn(address(this), _shares);
        }

        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    function _computeSTDepositCapacity() internal view returns (uint256) {
        /**
         * @dev Invariant: JT_NAV >= (JT_NAV + ST_Principal) * Coverage_%
         *      This is capped out when: JT_NAV == (JT_NAV + ST_Principal) * Coverage_%
         * @dev Solving for the max amount of assets we can deposit into the senior tranche, x:
         *      JT_NAV = (JT_NAV + (ST_Principal + x)) * Coverage_%
         *      x = (JT_NAV / Coverage_%) - JT_NAV - ST_Principal
         */

        // Retrieve the junior tranche net asset value
        uint256 jtNAV = RoycoSTStorageLib._getJuniorTranche().getNAV();
        if (jtNAV == 0) return 0;

        // Compute the total assets currently covered by the junior tranche
        // Round down in favor of the senior tranche
        uint256 totalCoveredNAV = jtNAV.mulDiv(ConstantsLib.WAD, RoycoSTStorageLib._getCoverageWAD(), Math.Rounding.Floor);
        // Get the current principal assets of the senior tranche
        uint256 stPrincipalAssets = RoycoSTStorageLib._getTotalPrincipalAssets();

        // Compute x, clipped to 0 to prevent underflow
        return Math.saturatingSub(totalCoveredNAV, jtNAV).saturatingSub(stPrincipalAssets);
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return RoycoSTStorageLib._getDecimalsOffset();
    }
}
