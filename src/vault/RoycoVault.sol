// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata,
    IERC4626,
    Math
} from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import { IERC7540 } from "../interfaces/IERC7540.sol";
import { IERC7575 } from "../interfaces/IERC7575.sol";
import { IERC7887 } from "../interfaces/IERC7887.sol";
import { IRoycoVaultKernel } from "../interfaces/IRoycoVaultKernel.sol";
import { ConstantsLib } from "../libraries/ConstantsLib.sol";
import { RoycoNetVaultStorageLib } from "../libraries/RoycoNetVaultStorageLib.sol";
import { RoycoVaultKernelLib } from "../libraries/RoycoVaultKernelLib.sol";
import { CostBasisLedger } from "./CostBasisLedger.sol";

contract RoycoVault is Ownable2StepUpgradeable, ERC4626Upgradeable, CostBasisLedger, IERC7540, IERC7575, IERC7887 {
    /// @dev https://eips.ethereum.org/EIPS/eip-7540#request-ids
    /// @dev Returning the request ID as 0 signals that the requests must purely be discriminated by the controller
    uint256 private constant ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID = 0;

    using Math for uint256;
    using SafeERC20 for IERC20;

    error MaxDepositExceeded();
    error SenderIsNotOwnerOrOperator();
    error UnsupportedOperation();

    modifier onlyWhenDepositsAreAsync() {
        require(RoycoNetVaultStorageLib._getDepositType() == IRoycoVaultKernel.ActionType.ASYNC, UnsupportedOperation());
        _;
    }

    modifier onlyWhenDepositsAreSync() {
        require(RoycoNetVaultStorageLib._getDepositType() == IRoycoVaultKernel.ActionType.SYNC, UnsupportedOperation());
        _;
    }

    modifier onlyWhenWithdrawlsAreAsync() {
        require(RoycoNetVaultStorageLib._getWithdrawType() == IRoycoVaultKernel.ActionType.ASYNC, UnsupportedOperation());
        _;
    }

    modifier onlyWhenWithdrawsAreSync() {
        require(RoycoNetVaultStorageLib._getWithdrawType() == IRoycoVaultKernel.ActionType.SYNC, UnsupportedOperation());
        _;
    }

    modifier onlyWhenDepositCancellationIsSupported() {
        require(RoycoNetVaultStorageLib._SUPPORTS_DEPOSIT_CANCELLATION(), UnsupportedOperation());
        _;
    }

    modifier onlyWhenRedemptionCancellationIsSupported() {
        require(RoycoNetVaultStorageLib._SUPPORTS_REDEMPTION_CANCELLATION(), UnsupportedOperation());
        _;
    }

    modifier onlySelfOrOperator(address _self) {
        require(msg.sender == _self || RoycoNetVaultStorageLib._isOperator(_self, msg.sender), SenderIsNotOwnerOrOperator());
        _;
    }

    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _owner,
        address _kernel,
        address _asset,
        address _feeClaimant,
        uint24 _yieldFeeBPS,
        address _navOracle,
        bytes calldata _kernelInitParams
    )
        external
        initializer
    {
        // Initialize the parent contracts
        __ERC20_init_unchained(_name, _symbol);
        __ERC4626_init_unchained(IERC20(_asset));
        __Ownable_init_unchained(_owner);

        // Calculate the vault's decimal offset (curb inflation attacks)
        uint8 underlyingAssetDecimals = IERC20Metadata(_asset).decimals();
        uint8 decimalsOffset = underlyingAssetDecimals >= 18 ? 0 : (18 - underlyingAssetDecimals);

        // Initialize the Royco Net Vault state
        RoycoNetVaultStorageLib.__RoycoNetVault_init(msg.sender, _kernel, _feeClaimant, _yieldFeeBPS, decimalsOffset, _navOracle);

        // Initialize the kernel's state in the vault contract by delegating to the kernel
        RoycoVaultKernelLib._initialize(RoycoNetVaultStorageLib._getKernel(), _kernelInitParams);
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
    function deposit(uint256 _assets, address _receiver, address _controller) public override onlySelfOrOperator(_controller) returns (uint256 shares) {
        // TODO: Test fee logic

        // Assert that the user's deposited assets fall under the max limit
        uint256 maxAssets = maxDeposit(_receiver);
        require(_assets <= maxAssets, ERC4626ExceededMaxDeposit(_receiver, _assets, maxAssets));

        shares = _previewDeposit(_assets);

        if (RoycoNetVaultStorageLib._getDepositType() == IRoycoVaultKernel.ActionType.SYNC) {
            // Transfer the tokens to the vault and mint the shares
            _deposit(_msgSender(), _receiver, _assets, shares);
        } else {
            // The tokens were already transferred to the vault during requestDeposit, just mint the shares
            _mint(_receiver, shares);
        }

        // Update the cost basis ledger
        _updateCostBasisOnDeposit(_receiver, _assets);

        // Process the deposit in the underlying protocol by calling the Kernel
        RoycoVaultKernelLib._deposit(RoycoNetVaultStorageLib._getKernel(), asset(), _controller, _assets);

        emit Deposit(_msgSender(), _receiver, _assets, shares);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 _shares, address _receiver) public override returns (uint256) {
        return mint(_shares, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    function mint(uint256 _shares, address _receiver, address _controller) public override onlySelfOrOperator(_controller) returns (uint256 assets) {
        // TODO: Test fee logic

        // Assert that the shares minted to the user fall under the max limit
        uint256 maxShares = maxMint(_receiver);
        require(_shares <= maxShares, ERC4626ExceededMaxMint(_receiver, _shares, maxShares));

        // TODO: Formally verify that this always matches the cost basis, even when shares are minted async
        assets = _previewMint(_shares);

        if (RoycoNetVaultStorageLib._getDepositType() == IRoycoVaultKernel.ActionType.SYNC) {
            // Transfer the tokens to the vault and mint the shares
            _deposit(_msgSender(), _receiver, assets, _shares);
        } else {
            // The tokens were already transferred to the vault during requestDeposit, just mint the shares
            _mint(_receiver, _shares);
        }

        // Update the cost basis ledger
        _updateCostBasisOnDeposit(_receiver, assets);

        // Process the deposit in the underlying protocol by calling the Kernel
        RoycoVaultKernelLib._deposit(RoycoNetVaultStorageLib._getKernel(), asset(), _controller, assets);

        emit Deposit(_msgSender(), _receiver, assets, _shares);
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
        // TODO: Test fee logic

        // Assert that the shares being redeeemed by the user fall under the permissible limits
        uint256 maxShares = maxRedeem(_controller);
        require(_shares <= maxShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxShares));

        assets = _previewRedeem(_shares);

        // Update the cost basis ledger
        _updateCostBasisOnRedeem(_controller, balanceOf(_controller), _shares);

        if (RoycoNetVaultStorageLib._getDepositType() == IRoycoVaultKernel.ActionType.SYNC) {
            // Update the cost basis ledger
            _updateCostBasisOnRedeem(_controller, balanceOf(_controller), _shares);

            // Burn the owner's shares
            _burn(_controller, _shares);
        } else {
            // Do not burn shares, they were already burnt during requestRedeem

            }

        // Process the withdrawal from the underlying protocol by calling the kernel - it is expected thtat the kernel
        // transfers the assets directly to the recipient
        RoycoVaultKernelLib._withdraw(RoycoNetVaultStorageLib._getKernel(), asset(), _controller, assets, _receiver);

        emit Withdraw(_msgSender(), _receiver, _controller, assets, _shares);
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
        // TODO: Test fee logic

        // Assert that the assets being withdrawn by the user fall under the permissible limits
        uint256 maxAssets = maxWithdraw(_controller);
        require(_assets <= maxAssets, ERC4626ExceededMaxWithdraw(_controller, _assets, maxAssets));

        shares = _previewWithdraw(_assets);

        if (RoycoNetVaultStorageLib._getWithdrawType() == IRoycoVaultKernel.ActionType.SYNC) {
            // Update the cost basis ledger
            _updateCostBasisOnRedeem(_controller, balanceOf(_controller), shares);

            // Burn the owner's shares
            _burn(_controller, shares);
        } else {
            // Do nothing, the shares were already burnt during requestWithdraw
        }

        // Process the withdrawal from the underlying protocol by calling the kernel - it is expected that the kernel
        // transfers the assets directly to the recipient
        RoycoVaultKernelLib._withdraw(RoycoNetVaultStorageLib._getKernel(), asset(), _controller, _assets, _receiver);

        emit Withdraw(_msgSender(), _receiver, _controller, _assets, shares);
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
        onlyWhenDepositsAreAsync
        onlySelfOrOperator(_owner)
        returns (uint256 requestId)
    {
        // Transfer the assets from the owner to the vault
        address asset = asset();
        IERC20(asset).safeTransferFrom(_owner, address(this), _assets);

        // Queue the deposit request
        RoycoVaultKernelLib._requestDeposit(RoycoNetVaultStorageLib._getKernel(), asset, _controller, _assets);

        // Return a controller-discriminated request ID
        requestId = ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID;

        emit DepositRequest(_controller, _owner, requestId, msg.sender, _assets);
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function pendingDepositRequest(uint256, address _controller) external view override onlyWhenDepositsAreAsync returns (uint256) {
        return RoycoVaultKernelLib._pendingDepositRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function claimableDepositRequest(uint256, address _controller) external view override onlyWhenDepositsAreAsync returns (uint256) {
        return RoycoVaultKernelLib._claimableDepositRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    function requestRedeem(uint256 _shares, address _controller, address _owner) external override onlyWhenWithdrawlsAreAsync returns (uint256 requestId) {
        // Calculate the assets to redeem
        uint256 _assets = _previewRedeem(_shares);

        // Update the cost basis ledger
        _updateCostBasisOnRedeem(_owner, balanceOf(_owner), _shares);

        // Burn the shares from the owner
        _burn(_owner, _shares);

        // Queue the redeem request
        RoycoVaultKernelLib._requestWithdraw(RoycoNetVaultStorageLib._getKernel(), asset(), _controller, _assets);

        // Return a controller-discriminated request ID
        requestId = ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID;

        emit RedeemRequest(_controller, _owner, requestId, msg.sender, _shares);

        return requestId;
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function pendingRedeemRequest(uint256, address _controller) external view override onlyWhenWithdrawlsAreAsync returns (uint256 pendingShares) {
        return RoycoVaultKernelLib._pendingRedeemRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    /// @notice The request id is ignored as the requests are controller-discriminated
    function claimableRedeemRequest(uint256, address _controller) external view override onlyWhenWithdrawlsAreAsync returns (uint256 claimableShares) {
        return RoycoVaultKernelLib._claimableRedeemRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7540
    function isOperator(address _controller, address _operator) external view override returns (bool) {
        return RoycoNetVaultStorageLib._isOperator(_controller, _operator);
    }

    /// @inheritdoc IERC7540
    function setOperator(address _operator, bool _approved) external override returns (bool) {
        RoycoNetVaultStorageLib._setOperator(msg.sender, _operator, _approved);
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
        RoycoVaultKernelLib._cancelDepositRequest(RoycoNetVaultStorageLib._getKernel(), _controller);

        emit CancelDepositRequest(_controller, ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function pendingCancelDepositRequest(uint256, address _controller) external view override onlyWhenDepositCancellationIsSupported returns (bool isPending) {
        return RoycoVaultKernelLib._pendingCancelDepositRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function claimableCancelDepositRequest(uint256, address _controller)
        external
        view
        override
        onlyWhenDepositCancellationIsSupported
        returns (uint256 assets)
    {
        return RoycoVaultKernelLib._claimableCancelDepositRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
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
        uint256 assets = RoycoVaultKernelLib._claimableCancelDepositRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);

        // Transfer assets to receiver
        IERC20(asset()).safeTransfer(_receiver, assets);

        emit CancelDepositClaim(_controller, _receiver, ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender, assets);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function cancelRedeemRequest(uint256, address _controller) external override onlyWhenRedemptionCancellationIsSupported onlySelfOrOperator(_controller) {
        // Delegate call to kernel to handle redeem cancellation
        RoycoVaultKernelLib._cancelRedeemRequest(RoycoNetVaultStorageLib._getKernel(), _controller);

        emit CancelRedeemRequest(_controller, ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function pendingCancelRedeemRequest(uint256, address _controller)
        external
        view
        override
        onlyWhenRedemptionCancellationIsSupported
        returns (bool isPending)
    {
        return RoycoVaultKernelLib._pendingCancelRedeemRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev The request id is ignored as the requests are controller-discriminated
    function claimableCancelRedeemRequest(
        uint256,
        address _controller
    )
        external
        view
        override
        onlyWhenRedemptionCancellationIsSupported
        returns (uint256 shares)
    {
        return RoycoVaultKernelLib._claimableCancelRedeemRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _controller);
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
        uint256 shares = RoycoVaultKernelLib._claimableCancelRedeemRequest(RoycoNetVaultStorageLib._getKernel(), asset(), _owner);

        // Mint shares to receiver
        _mint(_receiver, shares);

        emit CancelRedeemClaim(_owner, _receiver, ERC_7540_CONTROLLER_DISCRIMINATED_REQUEST_ID, msg.sender, shares);
    }

    /// @dev Override the ERC20 _update function to update the cost basis ledger
    function _update(address _from, address _to, uint256 _amount) internal virtual override {
        // If the transfer is not from the zero address to the zero address, it is a transfer between users
        if (_from != address(0) && _to != address(0)) {
            _updateCostBasisOnSharesTransferred(_from, _to, balanceOf(_from), _amount);
        }

        super._update(_from, _to, _amount);
    }

    /// @dev The total liabilities of the vault is the max of the total cost basis and the total assets
    function totalLiabilities() public view returns (uint256) {
        return Math.max(totalCostBasis(), totalAssets());
    }

    // =============================
    // Core ERC4626 view functions
    // =============================

    /// @inheritdoc IERC4626
    function totalAssets() public view override returns (uint256) {
        // TODO: Discuss/Test
        // The total assets managed by the vault is simply the total supply of shares multiplied by the NAV of the asset
        return Math.mulDiv(totalSupply(), RoycoNetVaultStorageLib._getNavOracle().getPrice(), ConstantsLib.RAY, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    /// @dev We do not enforce per user caps on deposits, so we can ignore the receiver param
    function maxDeposit(address) public view override returns (uint256) {
        return _maxAssetsDepositableGlobally();
    }

    /// @inheritdoc IERC4626
    /// @dev We do not enforce per user caps on mints, so we can ignore the receiver param
    function maxMint(address) public view override returns (uint256) {
        // NOTE: To prevent overflows on asset to share conversion
        // Premeptively return max if the globally depositable amount of assets is uncapped
        uint256 maxAssetsDepositableGlobally = _maxAssetsDepositableGlobally();
        if (maxAssetsDepositableGlobally == type(uint256).max) {
            return type(uint256).max;
        }
        // Preview deposit will handle computing the maximum mintable shares after applying accrued fees
        return _previewDeposit(maxAssetsDepositableGlobally);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address _owner) public view override returns (uint256) {
        // Calculate the max assets withdrable by the owner as the min of those held by the owner and globally withdrawable
        // Preview redeem will handle computing the max assets withdrawable by the owner after applying accrued fees
        return Math.min(_previewRedeem(balanceOf(_owner)), _maxAssetsWithdrawableGlobally());
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address _owner) public view override returns (uint256) {
        // NOTE: To prevent overflows on asset to share conversion
        // Premeptively return the owner's shares balance if the globally withdrawable amount of assets is uncapped
        uint256 maxAssetsWithdrawableGlobally = _maxAssetsWithdrawableGlobally();
        uint256 ownerSharesBalance = balanceOf(_owner);
        if (maxAssetsWithdrawableGlobally == type(uint256).max) {
            return ownerSharesBalance;
        }

        // Calculate the max shares redeemable by the owner as the minimum of globally redeemable and those held by the owner
        // Preview withdraw will handle computing the max shares redeemable by the owner after applying accrued fees
        return Math.min(previewWithdraw(maxAssetsWithdrawableGlobally), ownerSharesBalance);
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 _assets) public view override onlyWhenDepositsAreSync returns (uint256) {
        return _previewDeposit(_assets);
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 _shares) public view override onlyWhenDepositsAreSync returns (uint256) {
        return _previewMint(_shares);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 _assets) public view override onlyWhenWithdrawsAreSync returns (uint256) {
        return _previewWithdraw(_assets);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 _shares) public view override onlyWhenWithdrawsAreSync returns (uint256) {
        return _previewRedeem(_shares);
    }

    /// @inheritdoc IERC7575
    function share() external view override returns (address) {
        return address(this);
    }

    /// @inheritdoc IERC7575
    function vault(address _asset) external view override returns (address) {
        if (_asset == asset()) {
            return address(this);
        }
        return address(0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public pure returns (bool) {
        return (_interfaceId == type(IERC7540).interfaceId || _interfaceId == type(IERC7575).interfaceId || _interfaceId == type(IERC7887).interfaceId
                || _interfaceId == type(IERC4626).interfaceId);
    }

    function _previewDeposit(uint256 _assets) internal view returns (uint256) {
        // Calculate the expected shares minted for depositing the assets after simulating minting the accrued fee shares
        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToShares(_assets, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Floor);
    }

    function _previewMint(uint256 _shares) internal view returns (uint256) {
        // Calculate the assets needed to mint the expected shares after simulating minting the accrued fee shares
        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToAssets(_shares, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Ceil);
    }

    function _previewWithdraw(uint256 _assets) internal view returns (uint256) {
        // Calculate the assets withdrawn for redeeming the shares after simulating minting the accrued fee shares
        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToShares(_assets, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Ceil);
    }

    function _previewRedeem(uint256 _shares) internal view returns (uint256) {
        // Calculate the expected shares redeemed for withdrawing the assets after simulating minting the accrued fee shares

        (uint256 currentTotalAssets, uint256 feeSharesAccrued) = _getTotalAssetsAndFeeSharesAccrued();
        return _convertToAssets(_shares, totalSupply() + feeSharesAccrued, currentTotalAssets, Math.Rounding.Floor);
    }

    function _convertToShares(uint256 _assets, uint256 _newTotalShares, uint256 _newTotalAssets, Math.Rounding _rounding) internal view returns (uint256) {
        return _assets.mulDiv(_newTotalShares + 10 ** _decimalsOffset(), _newTotalAssets + 1, _rounding);
    }

    function _convertToAssets(uint256 _shares, uint256 _newTotalShares, uint256 _newTotalAssets, Math.Rounding _rounding) internal view returns (uint256) {
        return _shares.mulDiv(_newTotalAssets + 1, _newTotalShares + 10 ** _decimalsOffset(), _rounding);
    }

    function _maxAssetsDepositableGlobally() internal view returns (uint256) {
        return RoycoVaultKernelLib._maxDeposit(RoycoNetVaultStorageLib._getKernel(), asset());
    }

    function _maxAssetsWithdrawableGlobally() internal view returns (uint256) {
        return RoycoVaultKernelLib._maxWithdraw(RoycoNetVaultStorageLib._getKernel(), asset());
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return RoycoNetVaultStorageLib._getDecimalsOffset();
    }

    // TODO: Integrate
    function _getTotalAssetsAndFeeSharesAccrued() internal view returns (uint256 currentTotalAssets, uint256 feeSharesAccrued) {
        // Get the current and last checkpointed total assets
        currentTotalAssets = totalAssets();
        uint256 lastTotalAssets = RoycoNetVaultStorageLib._getLastTotalAssets();

        // If the vault accrued any yield, compute the fee on the yield
        if (currentTotalAssets > lastTotalAssets) {
            // Calculate the discrete yield accrued in assets
            uint256 yield = currentTotalAssets - lastTotalAssets;
            // Compute the fee deducted from the yield in assets
            uint256 yieldFee = yield.mulDiv(RoycoNetVaultStorageLib._getYieldFeeBPS(), RoycoNetVaultStorageLib.BPS_DENOMINATOR);
            // Convert the yield fee in assets to shares that will be minted to the fee recipient
            feeSharesAccrued = _convertToShares(yieldFee, totalSupply(), currentTotalAssets, Math.Rounding.Floor);
        }
    }
}
