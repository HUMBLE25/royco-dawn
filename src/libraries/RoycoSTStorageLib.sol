// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { ActionType, RoycoKernelLib } from "./RoycoKernelLib.sol";

/**
 * @notice Storage state for Royco Senior Tranche contracts
 * @custom:storage-location erc7201:Royco.storage.RoycoSTState
 * @custom:field royco - The address of the Royco factory contract
 * @custom:field kernel - The address of the kernel contract handling strategy logic
 * @custom:field juniorTranche - The address of the paired junior tranche
 * @custom:field rewardFeeWAD - The percentage of yield paid to protocol (WAD = 100%)
 * @custom:field feeClaimant - The address authorized to claim protocol fees
 * @custom:field coverageWAD - The percentage of senior tranche assets insured by junior tranche (WAD = 100%)
 * @custom:field decimalsOffset - Decimals offset for share token precision
 * @custom:field totalPrincipalAssets - The total principal currently deposited in the tranche (excludes PnL)
 * @custom:field lastTotalAssets - The last recorded total assets for yield calculation
 * @custom:field DEPOSIT_TYPE - The kernel action type for deposit operations
 * @custom:field WITHDRAW_TYPE - The kernel action type for withdrawal operations
 * @custom:field SUPPORTS_DEPOSIT_CANCELLATION - Whether the kernel supports deposit cancellation
 * @custom:field SUPPORTS_REDEMPTION_CANCELLATION - Whether the kernel supports redemption cancellation
 * @custom:field isOperator - Nested mapping tracking operator approvals for owners
 */
struct RoycoSTState {
    address royco;
    address kernel;
    address juniorTranche;
    uint64 rewardFeeWAD;
    address feeClaimant;
    uint64 coverageWAD; // The percentage of the senior tranche's total assets that will be insured by the junior tranche
    uint8 decimalsOffset;
    uint256 totalPrincipalAssets;
    uint256 lastTotalAssets;
    ActionType DEPOSIT_TYPE;
    ActionType WITHDRAW_TYPE;
    bool SUPPORTS_DEPOSIT_CANCELLATION;
    bool SUPPORTS_REDEMPTION_CANCELLATION;
    mapping(address owner => mapping(address operator => bool isOperator)) isOperator;
}

/**
 * @title RoycoSTStorageLib
 * @notice Library for managing Royco Senior Tranche storage using ERC-7201 pattern
 * @dev Provides functions to safely access and modify senior tranche state
 */
library RoycoSTStorageLib {
    /// @notice Maximum allowed yield fee (33% in WAD format)
    uint256 public constant MAX_YIELD_FEE_WAD = 0.33e18;

    /// @notice Thrown when attempting to set a fee above the maximum allowed
    error MAX_FEE_EXCEEDED();

    /// @dev Storage slot for RoycoSTState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.RoycoSTState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROYCO_ST_STORAGE_SLOT = 0x9aae6b709d857af2bed67bb686f14d35450d93e0187f3ff0787ddf0bec656100;

    /**
     * @notice Returns a reference to the RoycoSTState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage reference to the senior tranche state
     */
    function _getRoycoSTStorage() internal pure returns (RoycoSTState storage $) {
        assembly ("memory-safe") {
            $.slot := ROYCO_ST_STORAGE_SLOT
        }
    }

    /**
     * @notice Initializes the senior tranche storage state
     * @dev Sets up all initial parameters and validates fee constraints
     * @param _royco The address of the Royco factory contract
     * @param _kernel The address of the kernel contract handling strategy logic
     * @param _rewardFeeWAD The percentage of yield paid to protocol (WAD = 100%)
     * @param _feeClaimant The address authorized to claim protocol fees
     * @param _coverageWAD The percentage of senior tranche assets insured by junior tranche (WAD = 100%)
     * @param _juniorTranche The address of the paired junior tranche vault
     * @param _decimalsOffset Decimals offset for share token precision
     */
    function __RoycoST_init(
        address _royco,
        address _kernel,
        uint64 _rewardFeeWAD,
        address _feeClaimant,
        uint64 _coverageWAD,
        address _juniorTranche,
        uint8 _decimalsOffset
    )
        internal
    {
        // Check the protocol fee isn't greater than the max
        require(_rewardFeeWAD <= MAX_YIELD_FEE_WAD, MAX_FEE_EXCEEDED());

        // Set the initial state of the tranche
        RoycoSTState storage $ = _getRoycoSTStorage();
        $.royco = _royco;
        $.kernel = _kernel;
        $.juniorTranche = _juniorTranche;
        $.feeClaimant = _feeClaimant;
        $.rewardFeeWAD = _rewardFeeWAD;
        $.coverageWAD = _coverageWAD;
        $.decimalsOffset = _decimalsOffset;
        $.DEPOSIT_TYPE = RoycoKernelLib._DEPOSIT_TYPE(_kernel);
        $.WITHDRAW_TYPE = RoycoKernelLib._WITHDRAW_TYPE(_kernel);
        $.SUPPORTS_DEPOSIT_CANCELLATION = RoycoKernelLib._SUPPORTS_DEPOSIT_CANCELLATION(_kernel);
        $.SUPPORTS_REDEMPTION_CANCELLATION = RoycoKernelLib._SUPPORTS_REDEMPTION_CANCELLATION(_kernel);
    }

    /**
     * @notice Returns the address of the Royco factory contract
     * @return The factory contract address
     */
    function _getFactory() internal view returns (address) {
        return _getRoycoSTStorage().royco;
    }

    /**
     * @notice Returns the address of the kernel contract
     * @return The kernel contract address handling strategy logic
     */
    function _getKernel() internal view returns (address) {
        return _getRoycoSTStorage().kernel;
    }

    /**
     * @notice Returns the decimals offset for share token precision
     * @return The decimals offset value
     */
    function _getDecimalsOffset() internal view returns (uint8) {
        return _getRoycoSTStorage().decimalsOffset;
    }

    /**
     * @notice Returns the current reward fee percentage
     * @return The reward fee in WAD format (WAD = 100%)
     */
    function _getRewardFeeWAD() internal view returns (uint64) {
        return _getRoycoSTStorage().rewardFeeWAD;
    }

    /**
     * @notice Sets the yield fee percentage
     * @dev Validates that the fee does not exceed the maximum allowed
     * @param _rewardFeeWAD The new reward fee in WAD format (WAD = 100%)
     */
    function _setYieldFeeBPS(uint24 _rewardFeeWAD) internal {
        require(_rewardFeeWAD <= MAX_YIELD_FEE_WAD, MAX_FEE_EXCEEDED());
        _getRoycoSTStorage().rewardFeeWAD = _rewardFeeWAD;
    }

    /**
     * @notice Returns the total principal denominated in assets in the tranche
     * @return The total principal assets
     */
    function _getTotalPrincipalAssets() internal view returns (uint256) {
        return _getRoycoSTStorage().totalPrincipalAssets;
    }

    /**
     * @notice Returns the total principal denominated in assets in the tranche
     * @param _assets The assets added to the principal of the tranche
     */
    function _increaseTotalPrincipal(uint256 _assets) internal {
        _getRoycoSTStorage().totalPrincipalAssets += _assets;
    }

    /**
     * @notice Returns the total principal denominated in assets in the tranche
     * @param _assets The assets removed from the principal of the tranche
     */
    function _decreaseTotalPrincipal(uint256 _assets) internal {
        _getRoycoSTStorage().totalPrincipalAssets -= _assets;
    }

    /**
     * @notice Returns the last recorded total assets for yield calculation
     * @return The last total assets amount
     */
    function _getLastTotalAssets() internal view returns (uint256) {
        return _getRoycoSTStorage().lastTotalAssets;
    }

    /**
     * @notice Updates the last recorded total assets
     * @param _newLastTotalAssets The new total assets amount to record
     */
    function _setLastTotalAssets(uint256 _newLastTotalAssets) internal {
        _getRoycoSTStorage().lastTotalAssets = _newLastTotalAssets;
    }

    /**
     * @notice Checks if an operator is approved for a given owner
     * @param _owner The owner address
     * @param _operator The operator address to check
     * @return True if the operator is approved, false otherwise
     */
    function _isOperator(address _owner, address _operator) internal view returns (bool) {
        return _getRoycoSTStorage().isOperator[_owner][_operator];
    }

    /**
     * @notice Sets operator approval for an owner
     * @param _owner The owner address
     * @param _operator The operator address
     * @param _approved Whether the operator is approved
     */
    function _setOperator(address _owner, address _operator, bool _approved) internal {
        _getRoycoSTStorage().isOperator[_owner][_operator] = _approved;
    }

    /**
     * @notice Returns the kernel action type for deposit operations
     * @return The deposit action type from the kernel
     */
    function _getDepositType() internal view returns (ActionType) {
        return _getRoycoSTStorage().DEPOSIT_TYPE;
    }

    /**
     * @notice Returns the kernel action type for withdrawal operations
     * @return The withdrawal action type from the kernel
     */
    function _getWithdrawType() internal view returns (ActionType) {
        return _getRoycoSTStorage().WITHDRAW_TYPE;
    }

    /**
     * @notice Returns the junior tranche vault as an ERC4626 interface
     * @return The junior tranche vault contract
     */
    function _getJuniorTranche() internal view returns (IERC4626) {
        return IERC4626(_getRoycoSTStorage().juniorTranche);
    }

    /**
     * @notice Returns the coverage percentage
     * @return The percentage of senior tranche assets insured by junior tranche (WAD = 100%)
     */
    function _getCoverageWAD() internal view returns (uint64) {
        return _getRoycoSTStorage().coverageWAD;
    }

    /**
     * @notice Returns whether the kernel supports deposit cancellation
     * @return True if deposit cancellation is supported, false otherwise
     */
    function _SUPPORTS_DEPOSIT_CANCELLATION() internal view returns (bool) {
        return _getRoycoSTStorage().SUPPORTS_DEPOSIT_CANCELLATION;
    }

    /**
     * @notice Returns whether the kernel supports redemption cancellation
     * @return True if redemption cancellation is supported, false otherwise
     */
    function _SUPPORTS_REDEMPTION_CANCELLATION() internal view returns (bool) {
        return _getRoycoSTStorage().SUPPORTS_REDEMPTION_CANCELLATION;
    }
}
