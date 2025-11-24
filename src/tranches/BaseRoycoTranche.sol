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
/**
 * @title BaseRoycoTranche
 * @notice Abstract base contract implementing core functionality for Royco tranches
 * @dev This contract provides common tranche operations including ERC4626 vault functionality,
 *      asynchronous deposit/withdrawal support via ERC7540, and request cancellation via ERC7887
 *      All asset management and investment operations are delegated to the configured kernel
 */
abstract contract BaseRoycoTranche is IRoycoTranche, Ownable2StepUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Thrown when attempting to use disabled functionality
    error DISABLED();

    /// @notice Thrown when the caller is not the expected account or an approved operator
    error ONLY_CALLER_OR_OPERATOR();

    /// @notice Thrown when configuring this Royco market with an invalid coverage requirement
    error INVALID_COVERAGE_REQUIREMENT();

    /// @notice Thrown when junior tranche coverage is insufficient for the operation
    error INSUFFICIENT_JUNIOR_TRANCHE_COVERAGE();

    /**
     * @notice Modifier to ensure the specified action type uses a synchronous execution model
     * @param _actionType The action type to check (DEPOSIT or WITHDRAWAL)
     * @dev Reverts if the execution model is asynchronous
     */
    modifier executionIsSync(ActionType _actionType) {
        require(
            (_actionType == ActionType.DEPOSIT ? RoycoTrancheStorageLib._getDepositExecutionModel() : RoycoTrancheStorageLib._getWithdrawalExecutionModel())
                == ExecutionModel.SYNC,
            DISABLED()
        );
        _;
    }

    /**
     * @notice Modifier to ensure caller is either the specified address or an approved operator
     * @param _account The address that the caller should match or have operator approval for
     * @dev Reverts if caller is neither the address nor an approved operator
     */
    modifier onlyCallerOrOperator(address _account) {
        require(msg.sender == _account || RoycoTrancheStorageLib._isOperator(_account, msg.sender), ONLY_CALLER_OR_OPERATOR());
        _;
    }

    /**
     * @notice Post-condition that enforces the market's coverage requirement
     * @dev Coverage condition: JT_NAV >= (JT_NAV + ST_Principal) * Coverage_%
     *      If this fails, junior capital is insufficient to meet the coverage requirement for the senior principal
     * @dev Failure Modes:
     *      1. Synchronous:  Junior capital is insufficient purely because of too many senior deposits or junior withdrawals
     *      2. Asynchronous: Junior capital is insufficient because it incurred a loss proportionally greater than what senior capital did
     *                       Theoretically, this should not happen since junior will be deployed into the RFR or the same opportunity as senior
     */
    modifier checkCoverage() {
        // Coverage must be checked after all state changes have been applied
        _;
        uint256 jtNAV = _getJuniorTrancheNAV();
        uint256 requiredCoverageAssets = (jtNAV + _getSeniorTranchePrincipal()).mulDiv(RoycoTrancheStorageLib._getCoverageWAD(), ConstantsLib.WAD);
        require(jtNAV >= requiredCoverageAssets, INSUFFICIENT_JUNIOR_TRANCHE_COVERAGE());
    }

    /**
     * @notice Initializes the Royco tranche
     * @dev This function initializes parent contracts and the tranche-specific state
     * @param _trancheParams Deployment parameters including name, symbol, kernel, and kernel initialization data
     * @param _asset The underlying asset for the tranche
     * @param _owner The initial owner of the tranche
     * @param _coverageWAD The coverage ratio in WAD format (1e18 = 100%)
     * @param _complementTranche The address of the paired tranche (junior for senior, senior for junior)
     */
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

    /**
     * @notice Internal initialization function for Royco tranche-specific state
     * @dev This function sets up the tranche storage and initializes the kernel
     * @param _asset The underlying asset for the tranche
     * @param _kernel The kernel that handles strategy logic
     * @param _kernelInitCallData Initialization data for the kernel
     * @param _coverageWAD The coverage ratio in WAD format (1e18 = 100%)
     * @param _complementTranche The address of the paired tranche
     */
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
        // Check that the coverage requirement is valid
        require(_coverageWAD >= ConstantsLib.MIN_COVERAGE_WAD && _coverageWAD < ConstantsLib.WAD, INVALID_COVERAGE_REQUIREMENT());

        // Calculate the vault's decimal offset (curb inflation attacks)
        uint8 underlyingAssetDecimals = IERC20Metadata(_asset).decimals();
        uint8 decimalsOffset = underlyingAssetDecimals >= 18 ? 0 : (18 - underlyingAssetDecimals);

        // Initialize the tranche's state
        RoycoTrancheStorageLib.__RoycoTranche_init(msg.sender, _kernel, _coverageWAD, _complementTranche, decimalsOffset);

        // Initialize the kernel's state
        RoycoKernelLib.__Kernel_init(_kernel, _kernelInitCallData);
    }

    /// @inheritdoc IRoycoTranche
    function getNAV() external view override(IRoycoTranche) returns (uint256) {
        return RoycoKernelLib._getNAV(RoycoTrancheStorageLib._getKernel(), asset());
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Must be overridden by senior and junior tranches to account for loss coverage and yield accrual
    function totalAssets() public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Ensures all tranche operations is disabled unless overriden
        revert DISABLED();
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxDeposit(address _receiver) public view override(ERC4626Upgradeable) returns (uint256) {
        // Return the minimum of the deposit capacity of the underlying investment opportunity and the tranche
        return Math.min(RoycoKernelLib._maxDeposit(RoycoTrancheStorageLib._getKernel(), _receiver, asset()), _getTrancheDepositCapacity());
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxMint(address _receiver) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Preview deposit will handle computing the maximum mintable shares for the max assets depositable
        return super.previewDeposit(maxDeposit(_receiver));
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxWithdraw(address _owner) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Get the maximum globally withdrawable assets
        uint256 maxAssetsWithdrawable = RoycoKernelLib._maxWithdraw(RoycoTrancheStorageLib._getKernel(), _owner, asset());
        // Return the minimum of the globally withdrawable assets, assets owned by the owner, and the tranche's withdrawal capacity
        return Math.min(maxAssetsWithdrawable, super.previewRedeem(balanceOf(_owner))).min(_getTrancheWithdrawalCapacity());
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Should be overridden by junior tranches to check for withdrawal capacity
    function maxRedeem(address _owner) public view virtual override(ERC4626Upgradeable) returns (uint256) {
        // Preview withdraw will handle computing the maximum redeemable shares for the max assets withdrawable by the owner
        return super.previewWithdraw(maxWithdraw(_owner));
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewDeposit(uint256 _assets) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.DEPOSIT) returns (uint256) {
        return super.previewDeposit(_assets);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Disabled if deposit execution is asynchronous as per ERC7540
    function previewMint(uint256 _shares) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.DEPOSIT) returns (uint256) {
        return super.previewMint(_shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Disabled if withdrawal execution is asynchronous as per ERC7540
    function previewWithdraw(uint256 _assets) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.WITHDRAWAL) returns (uint256) {
        return super.previewWithdraw(_assets);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Disabled if withdrawal execution is asynchronous as per ERC7540
    function previewRedeem(uint256 _shares) public view virtual override(ERC4626Upgradeable) executionIsSync(ActionType.WITHDRAWAL) returns (uint256) {
        return super.previewRedeem(_shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 _assets, address _receiver) public virtual override(ERC4626Upgradeable) returns (uint256) {
        return deposit(_assets, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    /// @dev Should be overridden by senior tranches to check the coverage condition
    function deposit(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(IERC7540)
        onlyCallerOrOperator(_controller)
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

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 _shares, address _receiver) public virtual override(ERC4626Upgradeable) returns (uint256) {
        return mint(_shares, _receiver, msg.sender);
    }

    /// @inheritdoc IERC7540
    /// @dev Should be overridden by senior tranches to check the coverage condition
    function mint(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(IERC7540)
        onlyCallerOrOperator(_controller)
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
    /// @dev Should be overridden by junior tranches to check the coverage condition
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(ERC4626Upgradeable, IERC7540)
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

    /// @inheritdoc IERC7540
    /// @dev Should be overridden by junior tranches to check the coverage condition
    function redeem(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        virtual
        override(ERC4626Upgradeable, IERC7540)
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
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function requestDeposit(
        uint256 _assets,
        address _controller,
        address _owner
    )
        external
        virtual
        override(IERC7540)
        onlyCallerOrOperator(_owner)
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
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function pendingDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256) {
        return RoycoKernelLib._pendingDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function claimableDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256) {
        return RoycoKernelLib._claimableDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function requestRedeem(uint256 _shares, address _controller, address _owner) external virtual override(IERC7540) returns (uint256 requestId) {
        // Spend the caller's share allowance if the caller isn't the owner or an approved operator
        if (msg.sender != _owner && !RoycoTrancheStorageLib._isOperator(_owner, msg.sender)) _spendAllowance(_owner, msg.sender, _shares);
        // Transfer and lock the requested shares being redeemed from the owner to the tranche
        /// @dev Don't burn the shares so that total supply remains unchanged while this request is unclaimed
        _transfer(_owner, address(this), _shares);

        // Calculate the assets to redeem
        uint256 _assets = super.previewRedeem(_shares);

        // Queue the redemption request and get the request ID from the kernel
        requestId = RoycoKernelLib._requestRedeem(RoycoTrancheStorageLib._getKernel(), _assets, _shares, _controller);

        emit RedeemRequest(_controller, _owner, requestId, msg.sender, _shares);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function pendingRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256 pendingShares) {
        return RoycoKernelLib._pendingRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7540
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function claimableRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7540) returns (uint256 claimableShares) {
        return RoycoKernelLib._claimableRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    // =============================
    // ERC-7887 Cancelation Functions
    // =============================

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function cancelDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) onlyCallerOrOperator(_controller) {
        // Delegate call to kernel to handle deposit cancellation
        RoycoKernelLib._cancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);

        emit CancelDepositRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function pendingCancelDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (bool isPending) {
        return RoycoKernelLib._pendingCancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an asynchronous deposit flow
    function claimableCancelDepositRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (uint256 assets) {
        return RoycoKernelLib._claimableCancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
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
        onlyCallerOrOperator(_controller)
    {
        // Get the claimable amount before claiming
        uint256 assets = RoycoKernelLib._claimableCancelDepositRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);

        // Transfer cancelled deposit assets to receiver
        _transferOut(_receiver, assets);

        emit CancelDepositClaim(_controller, _receiver, _requestId, msg.sender, assets);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function cancelRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) onlyCallerOrOperator(_controller) {
        // Delegate call to kernel to handle redeem cancellation
        RoycoKernelLib._cancelRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);

        emit CancelRedeemRequest(_controller, _requestId, msg.sender);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function pendingCancelRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (bool isPending) {
        return RoycoKernelLib._pendingCancelRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev This function's state visibility can't be restricted to view since we need to delegatecall the kernel to read state
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function claimableCancelRedeemRequest(uint256 _requestId, address _controller) external virtual override(IERC7887) returns (uint256 shares) {
        return RoycoKernelLib._claimableCancelRedeemRequest(RoycoTrancheStorageLib._getKernel(), _requestId, _controller);
    }

    /// @inheritdoc IERC7887
    /// @dev Will revert if this tranche does not employ an asynchronous withdrawal flow
    function claimCancelRedeemRequest(uint256 _requestId, address _receiver, address _owner) external virtual override(IERC7887) onlyCallerOrOperator(_owner) {
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
        return _interfaceId == type(IERC165).interfaceId || _interfaceId == type(ERC4626Upgradeable).interfaceId || _interfaceId == type(IERC7540).interfaceId
            || _interfaceId == type(IERC7575).interfaceId || _interfaceId == type(IERC7887).interfaceId || _interfaceId == type(IRoycoTranche).interfaceId;
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Should be overridden by the senior tranche to handle principal accounting
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual override(ERC4626Upgradeable) {
        // If deposits are synchronous, transfer the assets to the tranche and mint the shares
        if (RoycoTrancheStorageLib._getDepositExecutionModel() == ExecutionModel.SYNC) super._deposit(_caller, _receiver, _assets, _shares);
        // If deposits are asynchronous, only mint shares since assets were transfered in on the request
        else _mint(_receiver, _shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Should be overridden by the senior tranche to handle principal accounting
    /// @dev Doesn't transfer assets to the receiver. This is the responsibility of the kernel.
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

    /// @dev Returns the deposit capacity in assets based on the coverage requirement
    function _getTrancheDepositCapacity() internal view virtual returns (uint256);

    /// @dev Returns the withdrawal capacity in assets based on the coverage requirement
    function _getTrancheWithdrawalCapacity() internal view virtual returns (uint256);

    /// @dev Returns the net asset value of the junior tranche in the junior tranche's base asset
    function _getJuniorTrancheNAV() internal view virtual returns (uint256);

    /// @dev Returns the total principal assets for the senior tranche
    function _getSeniorTranchePrincipal() internal view virtual returns (uint256);

    /// @inheritdoc ERC4626Upgradeable
    function _decimalsOffset() internal view virtual override(ERC4626Upgradeable) returns (uint8) {
        return RoycoTrancheStorageLib._getDecimalsOffset();
    }
}
