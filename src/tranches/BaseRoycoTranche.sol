// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import { ERC20Upgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata,
    IERC4626,
    Math
} from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165, IERC7540, IERC7575, IERC7887, IRoycoTranche } from "../interfaces/tranche/IRoycoTranche.sol";
import { ConstantsLib } from "../libraries/ConstantsLib.sol";
import { ExecutionModel, RoycoKernelLib } from "../libraries/RoycoKernelLib.sol";
import { RoycoTrancheStorageLib } from "../libraries/RoycoTrancheStorageLib.sol";
import { ActionType, TrancheDeploymentParams } from "../libraries/Types.sol";

// TODO: ST and JT base asset can have different decimals
abstract contract BaseRoycoTranche is IRoycoTranche, Ownable2StepUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    error DISABLED();
    error INVALID_CALLER();
    error INSUFFICIENT_JUNIOR_TRANCHE_COVERAGE();

    modifier executionIsSync(ActionType _actionType) {
        require(
            (_actionType == ActionType.DEPOSIT ? RoycoTrancheStorageLib._getDepositExecutionModel() : RoycoTrancheStorageLib._getWithdrawalExecutionModel())
                == ExecutionModel.SYNC,
            DISABLED()
        );
        _;
    }

    modifier onlySelfOrOperator(address _self) {
        require(msg.sender == _self || RoycoTrancheStorageLib._isOperator(_self, msg.sender), INVALID_CALLER());
        _;
    }

    function __RoycoTranche_init(
        TrancheDeploymentParams calldata _trancheParams,
        address _asset,
        address _owner,
        uint64 _coverageWAD,
        address _complementTranche
    )
        internal
        onlyInitializing
    {
        // Initialize the parent contracts
        __ERC20_init_unchained(_trancheParams.name, _trancheParams.symbol);
        __ERC4626_init_unchained(IERC20(_asset));
        __Ownable_init_unchained(_owner);

        // Initialize the Royco Tranche state
        __RoycoTranche_init_unchained(_asset, _trancheParams.kernel, _trancheParams.kernelInitCallData, _coverageWAD, _complementTranche);
    }

    function __RoycoTranche_init_unchained(
        address _asset,
        address _kernel,
        bytes calldata _kernelInitCallData,
        uint64 _coverageWAD,
        address _complementTranche
    )
        internal
        onlyInitializing
    {
        // Calculate the vault's decimal offset (curb inflation attacks)
        uint8 underlyingAssetDecimals = IERC20Metadata(_asset).decimals();
        uint8 decimalsOffset = underlyingAssetDecimals >= 18 ? 0 : (18 - underlyingAssetDecimals);

        // Initialize the senior tranche state
        RoycoTrancheStorageLib.__RoycoTranche_init(msg.sender, _kernel, _coverageWAD, _complementTranche, decimalsOffset);

        // Initialize the kernel's state
        RoycoKernelLib.__Kernel_init(_kernel, _kernelInitCallData);
    }

    /// @inheritdoc IERC4626
    /// @dev Should be overridden by senior tranches to check for deposit capacity
    function maxDeposit(address _receiver) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Return the maximum depositable assets
        return RoycoKernelLib._maxDeposit(RoycoTrancheStorageLib._getKernel(), _receiver, asset());
    }

    /// @inheritdoc IERC4626
    function maxMint(address _receiver) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Preview deposit will handle computing the maximum mintable shares for the max assets depositable
        return super.previewDeposit(maxDeposit(_receiver));
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address _owner) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Preview redeem will handle computing the maximum withdrawable assets for the max redeemable shares
        return super.previewRedeem(maxRedeem(_owner));
    }

    /// @inheritdoc IERC4626
    /// @dev Should be overridden by junior tranches to check for withdrawal capacity
    function maxRedeem(address _owner) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Get the maximum globally withdrawable assets
        uint256 maxAssetsWithdrawable = RoycoKernelLib._maxWithdraw(RoycoTrancheStorageLib._getKernel(), _owner, asset());
        // Return the minimum of the shares equating to the maximum globally withdrawable assets and the shares held by the owner
        return Math.min(super.previewWithdraw(maxAssetsWithdrawable), balanceOf(_owner));
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewDeposit(uint256 _assets) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.DEPOSIT) returns (uint256) {
        return super.previewDeposit(_assets);
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewMint(uint256 _shares) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.DEPOSIT) returns (uint256) {
        return super.previewMint(_shares);
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if withdrawal execution is asynchronous as per ERC7540
    function previewWithdraw(uint256 _assets) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.WITHDRAWAL) returns (uint256) {
        return super.previewWithdraw(_assets);
    }

    /// @inheritdoc IERC4626
    /// @dev Disabled if withdrawal execution is asynchronous as per ERC7540
    function previewRedeem(uint256 _shares) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.WITHDRAWAL) returns (uint256) {
        return super.previewRedeem(_shares);
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 _assets, address _receiver) public virtual override(ERC4626Upgradeable) returns (uint256) {
        return deposit(_assets, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    /// @dev Should be overriden by senior tranches to check the coverage condition
    function deposit(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(IERC7540)
        onlySelfOrOperator(_controller)
        returns (uint256 shares)
    {
        // Assert that the user's deposited assets fall under the max limit
        uint256 maxDepositableAssets = maxDeposit(_receiver);
        require(_assets <= maxDepositableAssets, ERC4626ExceededMaxDeposit(_receiver, _assets, maxDepositableAssets));

        // Handle depositing assets and minting shares
        _deposit(msg.sender, _receiver, _assets, (shares = super.previewDeposit(_assets)));

        // Process the deposit into the underlying investment opportunity by calling the kernel
        RoycoKernelLib._deposit(RoycoTrancheStorageLib._getKernel(), asset(), _assets, _controller);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 _shares, address _receiver) public virtual override(ERC4626Upgradeable) returns (uint256) {
        return mint(_shares, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    /// @dev Should be overriden by senior tranches to check the coverage condition
    function mint(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(IERC7540)
        onlySelfOrOperator(_controller)
        returns (uint256 assets)
    {
        // Assert that the shares minted to the user fall under the max limit
        uint256 maxMintableShares = maxMint(_receiver);
        require(_shares <= maxMintableShares, ERC4626ExceededMaxMint(_receiver, _shares, maxMintableShares));

        // Handle depositing assets and minting shares
        _deposit(msg.sender, _receiver, (assets = super.previewMint(_shares)), _shares);

        // Process the deposit for the underlying investment opportunity by calling the kernel
        RoycoKernelLib._deposit(RoycoTrancheStorageLib._getKernel(), asset(), assets, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev Should be overriden by junior tranches to check the coverage condition
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
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
        RoycoKernelLib._withdraw(RoycoTrancheStorageLib._getKernel(), asset(), _assets, _controller, _receiver);
    }

    /// @inheritdoc IERC7540
    /// @dev Should be overriden by junior tranches to check the coverage condition
    function redeem(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        virtual
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
        RoycoKernelLib._withdraw(RoycoTrancheStorageLib._getKernel(), asset(), assets, _controller, _receiver);
    }

    // =============================
    // ERC7540 Asynchronous flow functions
    // =============================

    /// @inheritdoc IERC7540
    function isOperator(address _controller, address _operator) external view virtual override(IERC7540) returns (bool) {
        return RoycoTrancheStorageLib._isOperator(_controller, _operator);
    }

    /// @inheritdoc IERC7540
    function setOperator(address _operator, bool _approved) external virtual override(IERC7540) returns (bool) {
        // Set the operator's approval status for the caller
        RoycoTrancheStorageLib._setOperator(msg.sender, _operator, _approved);
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
        virtual
        override(IERC7540)
        onlySelfOrOperator(_owner)
        returns (uint256 requestId)
    {
        // Transfer the assets from the owner to the tranche
        /// @dev These assets must not be counted in the NAV (total assets). Enforced by the kernel.
        _transferIn(_owner, _assets);

        // Queue the deposit request and get the request ID from the kernel
        requestId = RoycoKernelLib._requestDeposit(RoycoTrancheStorageLib._getKernel(), _assets, _controller);

        emit DepositRequest(_controller, _owner, requestId, msg.sender, _assets);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function pendingDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256) {
        return RoycoKernelLib._pendingDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function claimableDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256) {
        return RoycoKernelLib._claimableDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function requestRedeem(uint256 _shares, address _controller, address _owner) external virtual override(IERC7540) returns (uint256 requestId) {
        // Spend the caller's share allowance if the caller isn't the owner or an approved operator
        if (msg.sender != _owner && !RoycoTrancheStorageLib._isOperator(_owner, msg.sender)) _spendAllowance(_owner, msg.sender, _shares);
        // Transfer and lock the requested shares being redeemed from the owner to the tranche
        // NOTE: We must not burn the shares so that total supply remains unchanged while this request is unclaimed
        _transfer(_owner, address(this), _shares);

        // Calculate the assets to redeem
        uint256 _assets = super.previewRedeem(_shares);

        // Queue the redemption request and get the request ID from the kernel
        requestId = RoycoKernelLib._requestRedeem(RoycoTrancheStorageLib._getKernel(), _assets, _shares, _controller);

        emit RedeemRequest(_controller, _owner, requestId, msg.sender, _shares);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function pendingRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256 pendingShares) {
        return RoycoKernelLib._pendingRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an async deposit flow
    function claimableRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256 claimableShares) {
        return RoycoKernelLib._claimableRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    // =============================
    // ERC-7887 Cancelation Functions
    // =============================

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function cancelDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) onlySelfOrOperator(_controller) {
        // Delegate call to kernel to handle deposit cancellation
        RoycoKernelLib._cancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);

        emit CancelDepositRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function pendingCancelDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (bool isPending) {
        return RoycoKernelLib._pendingCancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function claimableCancelDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (uint256 assets) {
        return RoycoKernelLib._claimableCancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async deposit request cancellation
    function claimCancelDepositRequest(
        uint256 _requestId,
        address _receiver,
        address _controller
    )
        external
        virtual
        override(IERC7887)
        onlySelfOrOperator(_controller)
    {
        // Get the claimable amount before claiming
        uint256 assets = RoycoKernelLib._claimableCancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);

        // Transfer cancelled deposit assets to receiver
        _transferOut(_receiver, assets);

        emit CancelDepositClaim(_controller, _receiver, _requestId, msg.sender, assets);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function cancelRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) onlySelfOrOperator(_controller) {
        // Delegate call to kernel to handle redeem cancellation
        RoycoKernelLib._cancelRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);

        emit CancelRedeemRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function pendingCancelRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (bool isPending) {
        return RoycoKernelLib._pendingCancelRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function claimableCancelRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (uint256 shares) {
        return RoycoKernelLib._claimableCancelRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not support async redemption request cancellation
    function claimCancelRedeemRequest(uint256 _requestId, address _receiver, address _owner) external virtual override(IERC7887) onlySelfOrOperator(_owner) {
        // Get the claimable amount before claiming
        uint256 shares = RoycoKernelLib._claimableCancelRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _owner);

        // Transfer the previously locked shares (on request) to the receiver
        _transfer(address(this), _receiver, shares);

        emit CancelRedeemClaim(_owner, _receiver, _requestId, msg.sender, shares);
    }

    /// @inheritdoc IERC7575
    function share() external view virtual override(IERC7575) returns (address) {
        return address(this);
    }

    /// @inheritdoc IERC7575
    function vault(address _asset) external view virtual override(IERC7575) returns (address) {
        return _asset == asset() ? address(this) : address(0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public pure virtual override(IERC165) returns (bool) {
        return _interfaceId == type(IERC165).interfaceId || _interfaceId == type(IERC7540).interfaceId || _interfaceId == type(IERC7575).interfaceId
            || _interfaceId == type(IERC7887).interfaceId || _interfaceId == type(IRoycoTranche).interfaceId;
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Should be overriden by the senior tranche to handle principal accounting
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual override(ERC4626Upgradeable) {
        // If deposits are synchronous, transfer the assets to the tranche and mint the shares
        if (RoycoTrancheStorageLib._getDepositExecutionModel() == ExecutionModel.SYNC) super._deposit(_caller, _receiver, _assets, _shares);
        // If deposits are asynchronous, only mint shares since assets were transfered in on the request
        else _mint(_receiver, _shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Should be overriden by the senior tranche to handle principal accounting
    /// @dev NOTE: Doesn't transfer assets to the receiver. This is the responsibility of the kernel.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares) internal virtual override(ERC4626Upgradeable) {
        // If withdrawals are synchronous, burn the shares from the owner
        if (RoycoTrancheStorageLib._getWithdrawalExecutionModel() == ExecutionModel.SYNC) {
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

    /// @inheritdoc ERC4626Upgradeable
    function _decimalsOffset() internal view virtual override(ERC4626Upgradeable) returns (uint8) {
        return RoycoTrancheStorageLib._getDecimalsOffset();
    }
}
