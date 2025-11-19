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
import { IERC165 } from "../../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import { IERC7540 } from "../../interfaces/IERC7540.sol";
import { IERC7575 } from "../../interfaces/IERC7575.sol";
import { IERC7887 } from "../../interfaces/IERC7887.sol";
import { IRoycoKernel } from "../../interfaces/IRoycoKernel.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";
import { ErrorsLib } from "../../libraries/ErrorsLib.sol";
import { RoycoKernelLib } from "../../libraries/RoycoKernelLib.sol";
import { RoycoSTStorageLib } from "../../libraries/RoycoSTStorageLib.sol";
import { TrancheDeploymentParams } from "../../libraries/Types.sol";

contract RoycoST is Ownable2StepUpgradeable, ERC4626Upgradeable, IERC7540, IERC7575, IERC7887 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @dev https://eips.ethereum.org/EIPS/eip-7540#request-ids
    /// @dev Returning the request ID as 0 signals that the requests must be discriminated purely by the controller
    uint256 private constant ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID = 0;

    error INVALID_CALLER();
    error UNSUPPORTED_OPERATION();
    error INSUFFICIENT_ASSETS_IN_JUNIOR_TRANCHE();

    modifier checkDepositSemantics(IRoycoKernel.ActionType _actionType) {
        require(RoycoSTStorageLib._getDepositType() == _actionType, UNSUPPORTED_OPERATION());
        _;
    }

    modifier checkWithdrawalSemantics(IRoycoKernel.ActionType _actionType) {
        require(RoycoSTStorageLib._getWithdrawType() == _actionType, UNSUPPORTED_OPERATION());
        _;
    }

    modifier onlyWhenDepositCancellationIsSupported() {
        require(RoycoSTStorageLib._SUPPORTS_DEPOSIT_CANCELLATION(), UNSUPPORTED_OPERATION());
        _;
    }

    modifier onlyWhenRedemptionCancellationIsSupported() {
        require(RoycoSTStorageLib._SUPPORTS_REDEMPTION_CANCELLATION(), UNSUPPORTED_OPERATION());
        _;
    }

    modifier onlySelfOrOperator(address _self) {
        require(msg.sender == _self || RoycoSTStorageLib._isOperator(_self, msg.sender), INVALID_CALLER());
        _;
    }

    modifier checkCoverageInvariant() {
        // Let the function body execute
        _;
        // TODO: Gas Optimize
        // Check invariant after all state changes have been applied
        // Invariant: junior tranche controlled assets >= (senior tranche principal * coverage percentage)
        uint256 coverageAssets = _computeExpectedCoverageAssets(RoycoSTStorageLib._getTotalPrincipalAssets());
        require(RoycoSTStorageLib._getJuniorTranche().totalAssets() >= coverageAssets, INSUFFICIENT_ASSETS_IN_JUNIOR_TRANCHE());
    }

    function initialize(
        TrancheDeploymentParams calldata _stParams,
        address _asset,
        address _owner,
        uint64 _rewardFeeWAD,
        address _feeClaimant,
        address _rdm,
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
        RoycoSTStorageLib.__RoycoST_init(msg.sender, _stParams.kernel, _rewardFeeWAD, _feeClaimant, _coverageWAD, _juniorTranche, decimalsOffset);

        // Initialize the kernel's state
        RoycoKernelLib.__Kernel_init(RoycoSTStorageLib._getKernel(), _stParams.kernelInitParams);
    }

    // =============================
    // Core ERC4626 Functions with support for
    // ERC7540 style asynchronous deposits and withdrawals if enabled
    // =============================

    /// @inheritdoc IERC4626
    function deposit(uint256 _assets, address _receiver) public override returns (uint256) {
        return deposit(_assets, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    function deposit(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        override
        onlySelfOrOperator(_controller)
        checkCoverageInvariant
        returns (uint256 shares)
    {
        // TODO: Fee and yield accrual logic
        // Assert that the user's deposited assets fall under the max limit
        uint256 maxDepositableAssets = maxDeposit(_receiver);
        require(_assets <= maxDepositableAssets, ERC4626ExceededMaxDeposit(_receiver, _assets, maxDepositableAssets));

        // Handle depositing assets and minting shares
        _deposit(msg.sender, _receiver, _assets, (shares = _previewDeposit(_assets)));

        // Process the deposit into the underlying investment opportunity by calling the kernel
        RoycoKernelLib._deposit(RoycoSTStorageLib._getKernel(), asset(), _controller, _assets);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 _shares, address _receiver) public override returns (uint256) {
        return mint(_shares, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    function mint(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        override
        onlySelfOrOperator(_controller)
        checkCoverageInvariant
        returns (uint256 assets)
    {
        // TODO: Fee and yield accrual logic
        // Assert that the shares minted to the user fall under the max limit
        uint256 maxMintableShares = maxMint(_receiver);
        require(_shares <= maxMintableShares, ERC4626ExceededMaxMint(_receiver, _shares, maxMintableShares));

        // Handle depositing assets and minting shares
        _deposit(msg.sender, _receiver, (assets = _previewMint(_shares)), _shares);

        // Process the deposit for the underlying investment opportunity by calling the kernel
        RoycoKernelLib._deposit(RoycoSTStorageLib._getKernel(), asset(), _controller, assets);
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
        // TODO: Fee and yield accrual logic
        // Assert that the assets being withdrawn by the user fall under the permissible limits
        uint256 maxWithdrawableAssets = maxWithdraw(_controller);
        require(_assets <= maxWithdrawableAssets, ERC4626ExceededMaxWithdraw(_controller, _assets, maxWithdrawableAssets));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, _assets, (shares = _previewWithdraw(_assets)));

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        RoycoKernelLib._withdraw(RoycoSTStorageLib._getKernel(), asset(), _controller, _assets, _receiver);
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
        // TODO: Fee and yield accrual logic
        // Assert that the shares being redeeemed by the user fall under the permissible limits
        uint256 maxRedeemableShares = maxRedeem(_controller);
        require(_shares <= maxRedeemableShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxRedeemableShares));

        // Handle burning shares and principal accouting on withdrawal
        _withdraw(msg.sender, _receiver, _controller, (assets = _previewRedeem(_shares)), _shares);

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        RoycoKernelLib._withdraw(RoycoSTStorageLib._getKernel(), asset(), _controller, assets, _receiver);
    }

    // =============================
    // ERC7540 asynchronous deposit and redeem requests with support for cancelation
    // =============================

    /// @inheritdoc IERC7540
    function requestDeposit(
        uint256 _assets,
        address _controller,
        address _owner
    )
        external
        override
        checkDepositSemantics(IRoycoKernel.ActionType.ASYNC)
        onlySelfOrOperator(_owner)
        returns (uint256)
    {
        // Transfer the assets from the owner to the vault
        address asset = asset();
        IERC20(asset).safeTransferFrom(_owner, address(this), _assets);

        // Queue the deposit request
        RoycoKernelLib._requestDeposit(RoycoSTStorageLib._getKernel(), asset, _controller, _assets);

        emit DepositRequest(_controller, _owner, ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender, _assets);

        // This signals that all deposit requests will be solely discriminated by the controller
        return ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID;
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function pendingDepositRequest(uint256, address _controller) external override checkDepositSemantics(IRoycoKernel.ActionType.ASYNC) returns (uint256) {
        return RoycoKernelLib._pendingDepositRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function claimableDepositRequest(uint256, address _controller) external override checkDepositSemantics(IRoycoKernel.ActionType.ASYNC) returns (uint256) {
        return RoycoKernelLib._claimableDepositRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    function requestRedeem(
        uint256 _shares,
        address _controller,
        address _owner
    )
        external
        override
        checkWithdrawalSemantics(IRoycoKernel.ActionType.ASYNC)
        returns (uint256)
    {
        // Calculate the assets to redeem
        uint256 _assets = _previewRedeem(_shares);

        // Debit shares from the owner
        _debitShares(_controller, _owner, _shares);

        // Queue the redeem request
        RoycoKernelLib._requestWithdraw(RoycoSTStorageLib._getKernel(), asset(), _controller, _assets);

        emit RedeemRequest(_controller, _owner, ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender, _shares);

        // This signals that all redemption requests will be solely discriminated by the controller
        return ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID;
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function pendingRedeemRequest(
        uint256,
        address _controller
    )
        external
        override
        checkWithdrawalSemantics(IRoycoKernel.ActionType.ASYNC)
        returns (uint256 pendingShares)
    {
        return RoycoKernelLib._pendingRedeemRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function claimableRedeemRequest(
        uint256,
        address _controller
    )
        external
        override
        checkWithdrawalSemantics(IRoycoKernel.ActionType.ASYNC)
        returns (uint256 claimableShares)
    {
        return RoycoKernelLib._claimableRedeemRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    function isOperator(address _controller, address _operator) external view override returns (bool) {
        return RoycoSTStorageLib._isOperator(_controller, _operator);
    }

    /// @inheritdoc IERC7540
    function setOperator(address _operator, bool _approved) external override returns (bool) {
        // Set the operator's approval status for the caller and return true
        RoycoSTStorageLib._setOperator(msg.sender, _operator, _approved);
        emit OperatorSet(msg.sender, _operator, _approved);
        return true;
    }

    // =============================
    // ERC-7887 Cancelation Functions
    // =============================

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller discriminated
    function cancelDepositRequest(uint256, address _controller) external override onlyWhenDepositCancellationIsSupported onlySelfOrOperator(_controller) {
        // Delegate call to kernel to handle deposit cancellation
        RoycoKernelLib._cancelDepositRequest(RoycoSTStorageLib._getKernel(), _controller);

        emit CancelDepositRequest(_controller, ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function pendingCancelDepositRequest(uint256, address _controller) external override onlyWhenDepositCancellationIsSupported returns (bool isPending) {
        return RoycoKernelLib._pendingCancelDepositRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function claimableCancelDepositRequest(uint256, address _controller) external override onlyWhenDepositCancellationIsSupported returns (uint256 assets) {
        return RoycoKernelLib._claimableCancelDepositRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function claimCancelDepositRequest(
        uint256,
        address _receiver,
        address _controller
    )
        external
        override
        onlyWhenDepositCancellationIsSupported
        onlySelfOrOperator(_controller)
    {
        // Get the claimable amount before claiming
        uint256 assets = RoycoKernelLib._claimableCancelDepositRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);

        // Transfer assets to receiver
        IERC20(asset()).safeTransfer(_receiver, assets);

        emit CancelDepositClaim(_controller, _receiver, ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender, assets);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function cancelRedeemRequest(uint256, address _controller) external override onlyWhenRedemptionCancellationIsSupported onlySelfOrOperator(_controller) {
        // Delegate call to kernel to handle redeem cancellation
        RoycoKernelLib._cancelRedeemRequest(RoycoSTStorageLib._getKernel(), _controller);

        emit CancelRedeemRequest(_controller, ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function pendingCancelRedeemRequest(uint256, address _controller) external override onlyWhenRedemptionCancellationIsSupported returns (bool isPending) {
        return RoycoKernelLib._pendingCancelRedeemRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function claimableCancelRedeemRequest(uint256, address _controller) external override onlyWhenRedemptionCancellationIsSupported returns (uint256 shares) {
        return RoycoKernelLib._claimableCancelRedeemRequest(RoycoSTStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function claimCancelRedeemRequest(
        uint256,
        address _receiver,
        address _owner
    )
        external
        override
        onlyWhenRedemptionCancellationIsSupported
        onlySelfOrOperator(_owner)
    {
        // Get the claimable amount before claiming
        uint256 shares = RoycoKernelLib._claimableCancelRedeemRequest(RoycoSTStorageLib._getKernel(), asset(), _owner);

        // Mint shares to receiver
        _mint(_receiver, shares);

        emit CancelRedeemClaim(_owner, _receiver, ERC7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender, shares);
    }

    // =============================
    // Core ERC4626 view functions
    // =============================

    /// @inheritdoc IERC4626
    /// @dev Returns the senior tranche's effective total assets after factoring in losses covered by the junior tranche
    function totalAssets() public view override returns (uint256) {
        // Get the NAV of the senior tranche and principal deployed into the investment
        uint256 stAssets = RoycoKernelLib._totalAssets(RoycoSTStorageLib._getKernel(), asset());
        uint256 stPrincipal = RoycoSTStorageLib._getTotalPrincipalAssets();

        // Senior tranche is completely whole, without any coverage required from junior capital
        if (stAssets >= stPrincipal) return stAssets;

        // Senior tranche NAV has incurred a loss
        // Compute the actual amount of coverage provided by the junior tranche as the minimum of what they committed to insuring and their current NAV
        // This should always be equal to the expected coverage assets, unless the junior tranche has taken a loss
        uint256 actualCoverageAssets = Math.min(_computeExpectedCoverageAssets(stPrincipal), RoycoSTStorageLib._getJuniorTranche().totalAssets());

        // Compute the result of the senior tranche bucket in the loss waterfall:
        // Case 1: Senior tranche has suffered a loss that junior can absorb fully
        // The senior tranche principal is the effective NAV after partially or fully applying the coverage
        // Case 2: Senior tranche has suffered a loss greater than what junior can absorb
        // The actual assets controlled by the senior tranche in addition to all the coverage is the effective NAV
        return Math.min(stPrincipal, stAssets + actualCoverageAssets);
    }

    /// @inheritdoc IERC4626
    /// @dev We do not enforce per user caps on deposits, so we can ignore the receiver param
    function maxDeposit(address) public view override returns (uint256) {
        // Return the minimum of the asset capacity of the underlying investment opportunity and the senior tranche (to satisfy the coverage invariant)
        return Math.min(RoycoKernelLib._maxDeposit(RoycoSTStorageLib._getKernel(), asset()), _computeAssetCapacity());
    }

    /// @inheritdoc IERC4626
    /// @dev We do not enforce per user caps on mints, so we can ignore the receiver param
    function maxMint(address) public view override returns (uint256) {
        // Get the max assets depositable
        uint256 maxAssetsDepositable = maxDeposit(address(0));
        // Preview deposit will handle computing the maximum mintable shares after applying the yield distribution and accrued fees
        return _previewDeposit(maxAssetsDepositable);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address _owner) public view override returns (uint256) {
        // Return the minimum of the maximum globally withdrawable assets and the assets held by the owner
        // Preview redeem will handle computing the max assets withdrawable by the owner after applying the yield distribution and accrued fees
        return Math.min(RoycoKernelLib._maxWithdraw(RoycoSTStorageLib._getKernel(), asset()), _previewRedeem(balanceOf(_owner)));
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address _owner) public view override returns (uint256) {
        // Get the maximum globally withdrawable assets
        uint256 maxAssetsWithdrawable = RoycoKernelLib._maxWithdraw(RoycoSTStorageLib._getKernel(), asset());
        // Return the minimum of the shares equating to the maximum globally withdrawable assets and the shares held by the owner
        return Math.min(_previewWithdraw(maxAssetsWithdrawable), balanceOf(_owner));
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 _assets) public view override checkDepositSemantics(IRoycoKernel.ActionType.SYNC) returns (uint256) {
        return _previewDeposit(_assets);
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 _shares) public view override checkDepositSemantics(IRoycoKernel.ActionType.SYNC) returns (uint256) {
        return _previewMint(_shares);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 _assets) public view override checkWithdrawalSemantics(IRoycoKernel.ActionType.SYNC) returns (uint256) {
        return _previewWithdraw(_assets);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 _shares) public view override checkWithdrawalSemantics(IRoycoKernel.ActionType.SYNC) returns (uint256) {
        return _previewRedeem(_shares);
    }

    /// @inheritdoc IERC7575
    function share() external view override returns (address) {
        return address(this);
    }

    /// @inheritdoc IERC7575
    function vault(address _asset) external view override returns (address) {
        return _asset == asset() ? address(this) : address(0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public pure returns (bool) {
        return _interfaceId == this.supportsInterface.selector || _interfaceId == type(IERC4626).interfaceId || _interfaceId == type(IERC7540).interfaceId
            || _interfaceId == type(IERC7887).interfaceId;
    }

    function _previewDeposit(uint256 _assets) internal view returns (uint256) {
        // Calculate the shares minted for depositing the assets after simulating minting the accrued fee shares
        // Round in favor of the senior tranche
        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToShares(_assets, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Floor);
    }

    function _previewMint(uint256 _shares) internal view returns (uint256) {
        // Calculate the assets needed to mint the shares after simulating minting the accrued fee shares
        // Round in favor of the senior tranche
        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToAssets(_shares, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Ceil);
    }

    function _previewWithdraw(uint256 _assets) internal view returns (uint256) {
        // Calculate the shares that must be redeemed to withdraw the assets after simulating minting the accrued fee shares
        // Round in favor of the senior tranche
        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToShares(_assets, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Ceil);
    }

    function _previewRedeem(uint256 _shares) internal view returns (uint256) {
        // Calculate the assets withdrawn for redeeming the shares after simulating minting the accrued fee shares
        // Round in favor of the senior tranche
        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToAssets(_shares, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Floor);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Increases the total principal deposited into the tranche
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override(ERC4626Upgradeable) {
        // If deposits are synchronous, transfer the assets to the tranche and mint the shares
        if (RoycoSTStorageLib._getDepositType() == IRoycoKernel.ActionType.SYNC) _deposit(_caller, _receiver, _assets, _shares);
        // If deposits are asynchronous, only mint shares since assets were transfered in on the request
        else _mint(_receiver, _shares);

        // Increase the tranche's total principal by the assets being deposited
        RoycoSTStorageLib._increaseTotalPrincipal(_assets);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Decreases the total principal of assets deposited into the tranche
    /// @dev NOTE: Doesn't transfer assets to the receiver. This is the responsibility of the kernel.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares) internal override(ERC4626Upgradeable) {
        // Decrease the tranche's total principal by the assets being withdrawn
        RoycoSTStorageLib._decreaseTotalPrincipal(_assets);
        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);

        // No need to burn shares if withdrawals are asynchronous since they were burned on request
        if (RoycoSTStorageLib._getWithdrawType() == IRoycoKernel.ActionType.SYNC) _debitShares(_caller, _owner, _shares);
    }

    function _debitShares(address _caller, address _owner, uint256 _shares) internal {
        // Spend the caller's share allowance if the caller isn't the owner
        if (_caller != _owner) _spendAllowance(_owner, _caller, _shares);
        // Burn the shares being redeemed from the owner
        _burn(_owner, _shares);
    }

    function _computeExpectedCoverageAssets(uint256 _totalPrincipalAssets) internal view returns (uint256) {
        // Compute the assets required as coverage for the senior tranche
        // Round in favor of the senior tranche
        return _totalPrincipalAssets.mulDiv(RoycoSTStorageLib._getCoverageWAD(), ConstantsLib.WAD, Math.Rounding.Ceil);
    }

    function _computeAssetCapacity() internal view returns (uint256) {
        // Invariant: (senior tranche principal * coverage percentage) <= junior tranche controlled assets
        // This is maxed out when: (senior tranche principal * coverage percentage) == junior tranche controlled assets
        // Solving for the max amount of assets we can deposit, x, to satisfy this inequality:
        // ((senior tranche principal + x) * coverage percentage) == junior tranche controlled assets
        // x = (junior tranche controlled assets / coverage percentage) - senior tranche principal
        return RoycoSTStorageLib._getJuniorTranche().totalAssets().mulDiv(ConstantsLib.WAD, RoycoSTStorageLib._getCoverageWAD(), Math.Rounding.Floor) // Round down in favor of the senior tranche
            - RoycoSTStorageLib._getTotalPrincipalAssets();
    }

    // TODO: Write for yield/fee accrual and handling losses
    function _getTotalAssetsAndFeeSharesAccrued() internal view returns (uint256 currentTotalAssets, uint256 feeSharesAccrued) {
        // // Get the current and last checkpointed total assets
        // currentTotalAssets = totalAssets();
        // uint256 lastTotalAssets = RoycoSTStorageLib._getLastTotalAssets();

        // // If the vault accrued any yield, compute the fee on the yield
        // if (currentTotalAssets > lastTotalAssets) {
        //     // Calculate the discrete yield accrued in assets
        //     uint256 yield = currentTotalAssets - lastTotalAssets;
        //     // Compute the fee deducted from the yield in assets
        //     uint256 yieldFee = yield.mulDiv(RoycoSTStorageLib._getRewardFeeWAD(), RoycoSTStorageLib.BPS_DENOMINATOR);
        //     // Convert the yield fee in assets to shares that will be minted to the fee recipient
        //     feeSharesAccrued = _convertToShares(yieldFee, totalSupply(), currentTotalAssets, Math.Rounding.Floor);
        // }
    }

    function _convertToShares(uint256 _assets, uint256 _newTotalShares, uint256 _newTotalAssets, Math.Rounding _rounding) internal view returns (uint256) {
        return _assets.mulDiv(_newTotalShares + 10 ** _decimalsOffset(), _newTotalAssets + 1, _rounding);
    }

    function _convertToAssets(uint256 _shares, uint256 _newTotalShares, uint256 _newTotalAssets, Math.Rounding _rounding) internal view returns (uint256) {
        return _shares.mulDiv(_newTotalAssets + 1, _newTotalShares + 10 ** _decimalsOffset(), _rounding);
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return RoycoSTStorageLib._getDecimalsOffset();
    }
}
