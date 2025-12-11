// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata,
    Math
} from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IAccessControlEnumerable } from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlEnumerableUpgradeable, RoycoAuth, RoycoRoles } from "../auth/RoycoAuth.sol";
import { IAsyncJTDepositKernel } from "../interfaces/kernel/IAsyncJTDepositKernel.sol";
import { IAsyncJTWithdrawalKernel } from "../interfaces/kernel/IAsyncJTWithdrawalKernel.sol";
import { IAsyncSTDepositKernel } from "../interfaces/kernel/IAsyncSTDepositKernel.sol";
import { IAsyncSTWithdrawalKernel } from "../interfaces/kernel/IAsyncSTWithdrawalKernel.sol";
import { ExecutionModel, IBaseKernel } from "../interfaces/kernel/IBaseKernel.sol";
import { IERC165, IERC7540, IERC7575, IERC7887, IRoycoTranche } from "../interfaces/tranche/IRoycoTranche.sol";
import { RoycoTrancheStorageLib } from "../libraries/RoycoTrancheStorageLib.sol";
import { TrancheType } from "../libraries/Types.sol";
import { Action, TrancheDeploymentParams } from "../libraries/Types.sol";

/// @title BaseRoycoTranche
/// @notice Abstract base contract implementing core functionality for Royco tranches
/// @dev This contract provides common tranche operations including ERC4626 vault functionality,
///      asynchronous deposit/withdrawal support via ERC7540, and request cancellation via ERC7887
///      All asset management and investment operations are delegated to the configured kernel
abstract contract BaseRoycoTranche is IRoycoTranche, RoycoAuth, UUPSUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Thrown when attempting to use disabled functionality
    error DISABLED();

    /// @notice Thrown when the caller is not the expected account or an approved operator
    error ONLY_CALLER_OR_OPERATOR();

    /// @notice Thrown when the underlying shares allocated are greater than the total underlying shares
    error InvalidUnderlyingSharesAllocated(uint256 underlyingSharesAllocated, uint256 totalUnderlyingShares);

    /// @notice Thrown when the redeem amount is zero
    error ERC4626ZeroRedeemAmount();

    /// @notice Thrown when the deposit amount is zero
    error ERC4626ZeroDepositAmount();

    /// @notice Modifier to ensure the functionality is disabled
    // forge-lint: disable-next-line(unwrapped-modifier-logic)
    modifier disabled() {
        revert DISABLED();
        _;
    }

    /// @notice Modifier to ensure the specified action uses a synchronous execution model
    /// @param _action The action to check (DEPOSIT or WITHDRAW)
    /// @dev Reverts if the execution model for the action is asynchronous
    modifier executionIsSync(Action _action) {
        require(_isSync(_action), DISABLED());
        _;
    }

    /// @notice Modifier to ensure the specified action uses an asynchronous execution model
    /// @param _action The action to check (DEPOSIT or WITHDRAW)
    /// @dev Reverts if the execution model for the action is synchronous
    modifier executionIsAsync(Action _action) {
        require(!_isSync(_action), DISABLED());
        _;
    }

    /// @notice Modifier to ensure caller is either the specified address or an approved operator
    /// @param _account The address that the caller should match or have operator approval for
    /// @dev Reverts if caller is neither the address nor an approved operator
    modifier onlyCallerOrOperator(address _account) {
        _onlyCallerOrOperator(_account);
        _;
    }

    /// @notice Checks if the caller is either the specified address or an approved operator
    /// @param _account The address to check
    /// @dev Reverts if the caller is neither the address nor an approved operator
    function _onlyCallerOrOperator(address _account) internal view {
        require(msg.sender == _account || RoycoTrancheStorageLib._getRoycoTrancheStorage().isOperator[_account][msg.sender], ONLY_CALLER_OR_OPERATOR());
    }

    /// @notice Initializes the Royco tranche
    /// @dev This function initializes parent contracts and the tranche-specific state
    /// @param _trancheParams Deployment parameters including name, symbol, kernel, and kernel initialization data
    /// @param _asset The underlying asset for the tranche
    /// @param _owner The initial owner of the tranche
    /// @param _pauser The initial pauser of the tranche
    /// @param _marketId The identifier of the Royco market this tranche is linked to
    function __RoycoTranche_init(
        TrancheDeploymentParams calldata _trancheParams,
        address _asset,
        address _owner,
        address _pauser,
        bytes32 _marketId
    )
        internal
        onlyInitializing
    {
        // Initialize the parent contracts
        __ERC20_init_unchained(_trancheParams.name, _trancheParams.symbol);
        __ERC4626_init_unchained(IERC20(_asset));
        __RoycoAuth_init(_owner, _pauser);

        // Initialize the Royco Tranche state
        __RoycoTranche_init_unchained(_asset, _trancheParams.kernel, _marketId);
    }

    /// @notice Internal initialization function for Royco tranche-specific state
    /// @dev This function sets up the tranche storage and initializes the kernel
    /// @param _asset The underlying asset for the tranche
    /// @param _kernelAddress The address of the kernel that handles strategy logic
    /// @param _marketId The identifier of the Royco market this tranche is linked to
    function __RoycoTranche_init_unchained(address _asset, address _kernelAddress, bytes32 _marketId) internal onlyInitializing {
        // Calculate the vault's decimal offset (curb inflation attacks)
        uint8 underlyingAssetDecimals = IERC20Metadata(_asset).decimals();
        uint8 decimalsOffset = underlyingAssetDecimals >= 18 ? 0 : (18 - underlyingAssetDecimals);

        // Initialize the tranche's state
        RoycoTrancheStorageLib.__RoycoTranche_init(msg.sender, _kernelAddress, _marketId, decimalsOffset, TRANCHE_TYPE());
    }

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view virtual override(ERC4626Upgradeable) returns (uint256) {
        return (TRANCHE_TYPE() == TrancheType.SENIOR ? IBaseKernel(_kernel()).getSTTotalEffectiveAssets() : IBaseKernel(_kernel()).getJTTotalEffectiveAssets());
    }

    /// @inheritdoc IRoycoTranche
    function getNAV() external view override(IRoycoTranche) returns (uint256) {
        return (TRANCHE_TYPE() == TrancheType.SENIOR ? IBaseKernel(_kernel()).getSTEffectiveNAV() : IBaseKernel(_kernel()).getJTEffectiveNAV());
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxDeposit(address _receiver) public view override(ERC4626Upgradeable) returns (uint256) {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IBaseKernel(_kernel()).stMaxDeposit(asset(), _receiver)
                : IBaseKernel(_kernel()).jtMaxDeposit(asset(), _receiver));
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev mint* flows are not supported
    function maxMint(address _receiver) public view virtual override(ERC4626Upgradeable) disabled returns (uint256) { }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev withdraw* flows are not supported
    function maxWithdraw(address _owner) public view virtual override(ERC4626Upgradeable) disabled returns (uint256) { }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Should be overridden by junior tranches to check for withdrawal capacity
    function maxRedeem(address _owner) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        uint256 maxWithdrawable =
            (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IBaseKernel(_kernel()).stMaxWithdraw(asset(), _owner)
                : IBaseKernel(_kernel()).jtMaxWithdraw(asset(), _owner));

        return maxWithdrawable.mulDiv(totalSupply(), totalAssets(), Math.Rounding.Floor);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewDeposit(uint256 _assets) public view virtual override(ERC4626Upgradeable) executionIsSync(Action.DEPOSIT) returns (uint256) {
        return super.previewDeposit(_assets);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev mint* flows are not supported
    function previewMint(uint256 _shares) public view virtual override(ERC4626Upgradeable) disabled returns (uint256) { }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev withdraw* flows are not supported
    function previewWithdraw(uint256 _assets) public view virtual override(ERC4626Upgradeable) disabled returns (uint256) { }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Disabled if withdrawal execution is asynchronous as per ERC7540
    function previewRedeem(uint256 _shares) public view virtual override(ERC4626Upgradeable) executionIsSync(Action.WITHDRAW) returns (uint256) {
        return super.previewRedeem(_shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 _assets, address _receiver) public virtual override(ERC4626Upgradeable) returns (uint256) {
        return deposit(_assets, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    function deposit(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(IERC7540)
        checkRoleAndDelayIfGated(RoycoRoles.DEPOSIT_ROLE)
        whenNotPaused
        onlyCallerOrOperator(_controller)
        returns (uint256 shares)
    {
        // Assert that the user's deposited assets fall under the max limit
        uint256 maxDepositableAssets = maxDeposit(_receiver);
        require(_assets != 0, ERC4626ZeroDepositAmount());
        require(_assets <= maxDepositableAssets, ERC4626ExceededMaxDeposit(_receiver, _assets, maxDepositableAssets));

        IBaseKernel kernel = IBaseKernel(_kernel());
        IERC20 asset = IERC20(asset());

        // Transfer the assets from the receiver to the kernel, if the deposit is synchronous
        // If the deposit is asynchronous, the assets were transferred in during requestDeposit
        if (_isSync(Action.DEPOSIT)) {
            asset.safeTransferFrom(_receiver, address(kernel), _assets);
        }

        // Deposit the assets into the underlying investment opportunity and get the fraction of total assets allocated
        (uint256 underlyingSharesAllocated, uint256 totalEffectiveUnderlyingShares) = (TRANCHE_TYPE() == TrancheType.SENIOR
                ? kernel.stDeposit(address(asset), _assets, _controller, _receiver)
                : kernel.jtDeposit(address(asset), _assets, _controller, _receiver));
        require(
            underlyingSharesAllocated <= totalEffectiveUnderlyingShares,
            InvalidUnderlyingSharesAllocated(underlyingSharesAllocated, totalEffectiveUnderlyingShares)
        );

        // Calculate the proportional amount of shares to mint to the receiver such that lp_st_shares / total_st_shares = underlying_shares_allocated / total_underlying_shares
        // sharesToMint / (totalSupply() + 10 ** _decimalsOffset() + sharesToMint) = underlyingSharesAllocated / (totalEffectiveUnderlyingShares + 1)
        // In the synchronous case, this is equivalent to previewDeposit(_assets)
        // In the asynchronos case, the deposit request may not be have been fulfilled at the current nav.
        //  Therefore, the kernel is expected to keep track of the underlying opportunity shares minted against the request.
        //  The ratio of these shares to the total underlying shares held by the system represent the user's claim on the vault, therefore we mint
        //  an equivalent amount of shares to the receiver.
        shares = (totalSupply() + 10 ** _decimalsOffset())
        .mulDiv(underlyingSharesAllocated, totalEffectiveUnderlyingShares - underlyingSharesAllocated + 1, Math.Rounding.Floor);

        // Mint the shares to the receiver
        _mint(_receiver, shares);

        emit Deposit(msg.sender, _receiver, _assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev mint* flows are not supported
    function mint(uint256 _shares, address _receiver) public virtual override(ERC4626Upgradeable) disabled returns (uint256) { }

    /// @inheritdoc IERC7540
    /// @dev mint* flows are not supported
    function mint(uint256 _shares, address _receiver, address _controller) public virtual override(IERC7540) disabled returns (uint256 assets) { }

    /// @inheritdoc IERC7540
    /// @dev withdraw* flows are not supported
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(ERC4626Upgradeable, IERC7540)
        disabled
        returns (uint256 shares)
    { }

    /// @inheritdoc IERC7540
    function redeem(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(ERC4626Upgradeable, IERC7540)
        onlyCallerOrOperator(_controller)
        checkRoleAndDelayIfGated(RoycoRoles.REDEEM_ROLE)
        whenNotPaused
        returns (uint256 assets)
    {
        require(_shares != 0, ERC4626ZeroRedeemAmount());

        // Assert that the shares being redeeemed by the user fall under the permissible limits
        uint256 maxRedeemableShares = maxRedeem(_controller);
        require(_shares <= maxRedeemableShares, ERC4626ExceededMaxRedeem(_controller, _shares, maxRedeemableShares));

        // Process the withdrawal from the underlying investment opportunity
        // It is expected that the kernel transfers the assets directly to the receiver
        uint256 assetsWithdrawn =
            (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IBaseKernel(_kernel()).stRedeem(asset(), _shares, totalSupply(), _controller, _receiver)
                : IBaseKernel(_kernel()).jtRedeem(asset(), _shares, totalSupply(), _controller, _receiver));
        assets = assetsWithdrawn;

        // Account for the withdrawal
        _withdraw(msg.sender, _receiver, _controller, assets, _shares);
    }

    // =============================
    // ERC7540 Asynchronous flow functions
    // =============================

    /// @inheritdoc IERC7540
    function isOperator(address _controller, address _operator) external view virtual override(IERC7540) returns (bool) {
        return RoycoTrancheStorageLib._getRoycoTrancheStorage().isOperator[_controller][_operator];
    }

    /// @inheritdoc IERC7540
    function setOperator(address _operator, bool _approved) external virtual override(IERC7540) whenNotPaused returns (bool) {
        // Set the operator's approval status for the caller
        RoycoTrancheStorageLib._getRoycoTrancheStorage().isOperator[msg.sender][_operator] = _approved;
        emit OperatorSet(msg.sender, _operator, _approved);

        // Must return true as per ERC7540
        return true;
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function requestDeposit(
        uint256 _assets,
        address _controller,
        address _owner
    )
        external
        virtual
        override(IERC7540)
        checkRoleAndDelayIfGated(RoycoRoles.DEPOSIT_ROLE)
        whenNotPaused
        onlyCallerOrOperator(_owner)
        executionIsAsync(Action.DEPOSIT)
        returns (uint256 requestId)
    {
        address kernel = _kernel();

        // Transfer the assets from the owner to the kernel
        IERC20(asset()).safeTransferFrom(_owner, kernel, _assets);

        // Queue the deposit request and get the request ID from the kernel
        requestId =
        (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTDepositKernel(kernel).stRequestDeposit(msg.sender, _assets, _controller)
                : IAsyncJTDepositKernel(kernel).jtRequestDeposit(msg.sender, _assets, _controller));

        emit DepositRequest(_controller, _owner, requestId, msg.sender, _assets);
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function pendingDepositRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7540)
        executionIsAsync(Action.DEPOSIT)
        returns (uint256)
    {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTDepositKernel(_kernel()).stPendingDepositRequest(_requestId, _controller)
                : IAsyncJTDepositKernel(_kernel()).jtPendingDepositRequest(_requestId, _controller));
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function claimableDepositRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7540)
        executionIsAsync(Action.DEPOSIT)
        returns (uint256)
    {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTDepositKernel(_kernel()).stClaimableDepositRequest(_requestId, _controller)
                : IAsyncJTDepositKernel(_kernel()).jtClaimableDepositRequest(_requestId, _controller));
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function requestRedeem(
        uint256 _shares,
        address _controller,
        address _owner
    )
        external
        virtual
        override(IERC7540)
        checkRoleAndDelayIfGated(RoycoRoles.REDEEM_ROLE)
        whenNotPaused
        executionIsAsync(Action.WITHDRAW)
        returns (uint256 requestId)
    {
        require(_shares != 0, ERC4626ZeroRedeemAmount());

        // Spend the caller's share allowance if the caller isn't the owner or an approved operator
        if (msg.sender != _owner && !RoycoTrancheStorageLib._getRoycoTrancheStorage().isOperator[_owner][msg.sender]) {
            _spendAllowance(_owner, msg.sender, _shares);
        }
        // Transfer and lock the requested shares being redeemed from the owner to the tranche
        /// @dev Don't burn the shares so that total supply remains unchanged while this request is unclaimed
        _transfer(_owner, address(this), _shares);

        // Queue the redemption request and get the request ID from the kernel
        requestId =
        (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTWithdrawalKernel(_kernel()).stRequestWithdrawal(msg.sender, _shares, totalSupply(), _controller)
                : IAsyncJTWithdrawalKernel(_kernel()).jtRequestWithdrawal(msg.sender, _shares, totalSupply(), _controller));

        emit RedeemRequest(_controller, _owner, requestId, msg.sender, _shares);
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function pendingRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7540)
        executionIsAsync(Action.WITHDRAW)
        returns (uint256 pendingShares)
    {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTWithdrawalKernel(_kernel()).stPendingWithdrawalRequest(_requestId, totalSupply(), _controller)
                : IAsyncJTWithdrawalKernel(_kernel()).jtPendingWithdrawalRequest(_requestId, totalSupply(), _controller));
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function claimableRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7540)
        executionIsAsync(Action.WITHDRAW)
        returns (uint256 claimableShares)
    {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTWithdrawalKernel(_kernel()).stClaimableWithdrawalRequest(_requestId, totalSupply(), _controller)
                : IAsyncJTWithdrawalKernel(_kernel()).jtClaimableWithdrawalRequest(_requestId, totalSupply(), _controller));
    }

    // =============================
    // ERC-7887 Cancelation Functions
    // =============================

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function cancelDepositRequest(
        uint256 _requestId,
        address _controller
    )
        external
        virtual
        override(IERC7887)
        checkRoleAndDelayIfGated(RoycoRoles.CANCEL_DEPOSIT_ROLE)
        whenNotPaused
        onlyCallerOrOperator(_controller)
        executionIsAsync(Action.DEPOSIT)
    {
        if (TRANCHE_TYPE() == TrancheType.SENIOR) {
            IAsyncSTDepositKernel(_kernel()).stCancelDepositRequest(msg.sender, _requestId, _controller);
        } else {
            IAsyncJTDepositKernel(_kernel()).jtCancelDepositRequest(msg.sender, _requestId, _controller);
        }

        emit CancelDepositRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function pendingCancelDepositRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7887)
        executionIsAsync(Action.DEPOSIT)
        returns (bool isPending)
    {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTDepositKernel(_kernel()).stPendingCancelDepositRequest(_requestId, _controller)
                : IAsyncJTDepositKernel(_kernel()).jtPendingCancelDepositRequest(_requestId, _controller));
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function claimableCancelDepositRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7887)
        executionIsAsync(Action.DEPOSIT)
        returns (uint256 assets)
    {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTDepositKernel(_kernel()).stClaimableCancelDepositRequest(_requestId, _controller)
                : IAsyncJTDepositKernel(_kernel()).jtClaimableCancelDepositRequest(_requestId, _controller));
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function claimCancelDepositRequest(
        uint256 _requestId,
        address _receiver,
        address _controller
    )
        external
        virtual
        override(IERC7887)
        checkRoleAndDelayIfGated(RoycoRoles.CANCEL_DEPOSIT_ROLE)
        whenNotPaused
        onlyCallerOrOperator(_controller)
        executionIsAsync(Action.DEPOSIT)
    {
        // Expect the kernel to transfer the assets to the receiver directly after the cancellation is processed
        uint256 assets =
            (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTDepositKernel(_kernel()).stClaimCancelDepositRequest(_requestId, _receiver, _controller)
                : IAsyncJTDepositKernel(_kernel()).jtClaimCancelDepositRequest(_requestId, _receiver, _controller));

        emit CancelDepositClaim(_controller, _receiver, _requestId, msg.sender, assets);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function cancelRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        virtual
        override(IERC7887)
        checkRoleAndDelayIfGated(RoycoRoles.CANCEL_REDEEM_ROLE)
        whenNotPaused
        onlyCallerOrOperator(_controller)
        executionIsAsync(Action.WITHDRAW)
    {
        if (TRANCHE_TYPE() == TrancheType.SENIOR) {
            IAsyncSTWithdrawalKernel(_kernel()).stCancelWithdrawalRequest(_requestId, _controller);
        } else {
            IAsyncJTWithdrawalKernel(_kernel()).jtCancelWithdrawalRequest(_requestId, _controller);
        }

        emit CancelRedeemRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function pendingCancelRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7887)
        executionIsAsync(Action.WITHDRAW)
        returns (bool isPending)
    {
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTWithdrawalKernel(_kernel()).stPendingCancelWithdrawalRequest(_requestId, _controller)
                : IAsyncJTWithdrawalKernel(_kernel()).jtPendingCancelWithdrawalRequest(_requestId, _controller));
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function claimableCancelRedeemRequest(
        uint256 _requestId,
        address _controller
    )
        external
        view
        virtual
        override(IERC7887)
        executionIsAsync(Action.WITHDRAW)
        returns (uint256 shares)
    {
        // TODO: This funciton returns assets, not shares
        return (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTWithdrawalKernel(_kernel()).stClaimableCancelWithdrawalRequest(_requestId, _controller)
                : IAsyncJTWithdrawalKernel(_kernel()).jtClaimableCancelWithdrawalRequest(_requestId, _controller));
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function claimCancelRedeemRequest(
        uint256 _requestId,
        address _receiver,
        address _owner
    )
        external
        virtual
        override(IERC7887)
        checkRoleAndDelayIfGated(RoycoRoles.CANCEL_REDEEM_ROLE)
        whenNotPaused
        onlyCallerOrOperator(_owner)
        executionIsAsync(Action.WITHDRAW)
    {
        // TODO: This funciton returns assets, not shares

        // Get the claimable amount before claiming
        uint256 shares =
            (TRANCHE_TYPE() == TrancheType.SENIOR
                ? IAsyncSTWithdrawalKernel(_kernel()).stClaimableCancelWithdrawalRequest(_requestId, _owner)
                : IAsyncJTWithdrawalKernel(_kernel()).jtClaimableCancelWithdrawalRequest(_requestId, _owner));

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
    function supportsInterface(bytes4 _interfaceId) public pure virtual override(IERC165, AccessControlEnumerableUpgradeable) returns (bool) {
        return _interfaceId == type(IERC165).interfaceId || _interfaceId == type(ERC4626Upgradeable).interfaceId || _interfaceId == type(IERC7540).interfaceId
            || _interfaceId == type(IERC7575).interfaceId || _interfaceId == type(IERC7887).interfaceId || _interfaceId == type(IRoycoTranche).interfaceId
            || _interfaceId == type(IAccessControlEnumerable).interfaceId;
    }

    /// @dev Returns the type of the tranche
    function TRANCHE_TYPE() public pure virtual returns (TrancheType);

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Doesn't transfer assets to the receiver. This is the responsibility of the kernel.
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares) internal virtual override(ERC4626Upgradeable) {
        // If withdrawals are synchronous, burn the shares from the owner
        if (_isSync(Action.WITHDRAW)) {
            // Spend the caller's share allowance if the caller isn't the owner
            if (_caller != _owner) _spendAllowance(_owner, _caller, _shares);
            // Burn the shares being redeemed from the owner
            _burn(_owner, _shares);
        } else {
            // No need to spend allowance, that was already done during requestRedeem
            // If withdrawals are asynchronous, burn the shares that were locked in the tranche on requesting the redemption
            _burn(address(this), _shares);
        }

        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    /// @inheritdoc UUPSUpgradeable
    /// @dev Will revert if the caller is not the upgrader role
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(RoycoRoles.UPGRADER_ROLE) { }

    /// @dev Returns if the specified action employs a synchronous execution model
    function _isSync(Action _action) internal view returns (bool) {
        return (_action == Action.DEPOSIT
                    ? RoycoTrancheStorageLib._getRoycoTrancheStorage().DEPOSIT_EXECUTION_MODEL
                    : RoycoTrancheStorageLib._getRoycoTrancheStorage().WITHDRAW_EXECUTION_MODEL) == ExecutionModel.SYNC;
    }

    /// @inheritdoc ERC4626Upgradeable
    function _decimalsOffset() internal view virtual override(ERC4626Upgradeable) returns (uint8) {
        return RoycoTrancheStorageLib._getRoycoTrancheStorage().decimalsOffset;
    }

    function _kernel() internal view virtual returns (address) {
        return RoycoTrancheStorageLib._getRoycoTrancheStorage().kernel;
    }
}
