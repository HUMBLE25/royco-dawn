// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20Metadata } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol";
import { WAD } from "../../../libraries/Constants.sol";
import { NAV_UNIT, TRANCHE_UNIT, toNAVUnits, toTrancheUnits, toUint256 } from "../../../libraries/Units.sol";
import { RoycoKernel } from "../RoycoKernel.sol";

/**
 * @title OverridableNAVOracleIdenticalAssetsQuoter
 * @notice Quoter for markets that allocate to markets with identical TRANCHE_UNITs
 * @dev The quoter reads the conversion rate from the specified oracle in WAD precision.
 *      The kernel admin can optionally override the conversion rate with a fixed value.
 *      Supported use-cases include:
 *      - Allocating ST and JT accepting the ERC4626 Vault Share, but the NAV units differ from the tranche units. For example:
 *        - Yield Breaking ERC20 ST And JT: Tranche Unit (like NUSD, reUSD), NAV Unit (USD)
 */
abstract contract OverridableNAVOracleIdenticalAssetsQuoter is RoycoKernel {
    /// @dev Storage slot for OverridableNAVOracleIdenticalAssetsQuoterState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.OverridableNAVOracleIdenticalAssetsQuoterState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OVERRIDABLE_NAV_ORACLE_IDENTICAL_ASSETS_QUOTER_STORAGE_SLOT = 0x0785225953a08907d128280fd0b80854efdf826a489c9eefeeec6620bb9d6600;

    /// @dev Storage state for the Royco overridable oracle quoter
    /// @custom:storage-location erc7201:Royco.storage.OverridableNAVOracleIdenticalAssetsQuoterState
    struct OverridableNAVOracleIdenticalAssetsQuoterState {
        uint256 ratetrancheUnitToNAVUnitConversionRateWAD;
    }

    /// @notice Emitted when the tranche unit to NAV unit conversion rate is set
    event TrancheUnitToNAVUnitConversionRateSet(uint256 _trancheUnitToNAVUnitConversionRateWAD);

    /// @notice Thrown when the senior and junior tranche assets have the same precision
    error TRANCHE_ASSET_DECIMALS_MISMATCH();

    /// @notice Initializes the quoter for overridable oracle
    /// @param _initialConversionRateWAD The initial tranche unit to NAV unit conversion rate
    function __OverridableNAVOracleIdenticalAssetsQuoter_init_unchained(
        address _stAsset,
        address _jtAsset,
        uint256 _initialConversionRateWAD
    )
        internal
        onlyInitializing
    {
        // This quoter stipulates that both tranche assets have identical precision
        require(IERC20Metadata(_stAsset).decimals() == IERC20Metadata(_jtAsset).decimals(), TRANCHE_ASSET_DECIMALS_MISMATCH());

        if (_initialConversionRateWAD != 0) {
            OverridableNAVOracleIdenticalAssetsQuoterState storage $ = _getOverridableNAVOracleIdenticalAssetsQuoterStorage();
            $.ratetrancheUnitToNAVUnitConversionRateWAD = _initialConversionRateWAD;
            emit TrancheUnitToNAVUnitConversionRateSet(_initialConversionRateWAD);
        }
    }

    /// @notice Sets the tranche unit to NAV unit conversion rate
    /// @param _trancheUnitToNAVUnitConversionRateWAD The tranche unit to NAV unit conversion rate
    function setTrancheUnitToNAVUnitConversionRate(uint256 _trancheUnitToNAVUnitConversionRateWAD) external restricted {
        OverridableNAVOracleIdenticalAssetsQuoterState storage $ = _getOverridableNAVOracleIdenticalAssetsQuoterStorage();
        $.ratetrancheUnitToNAVUnitConversionRateWAD = _trancheUnitToNAVUnitConversionRateWAD;
        emit TrancheUnitToNAVUnitConversionRateSet(_trancheUnitToNAVUnitConversionRateWAD);
    }

    /// @inheritdoc RoycoKernel
    function stConvertTrancheUnitsToNAVUnits(TRANCHE_UNIT _stAssets) public view override(RoycoKernel) returns (NAV_UNIT nav) {
        return toNAVUnits(toUint256(_stAssets) * getTrancheUnitToNAVUnitConversionRate() / WAD);
    }

    /// @inheritdoc RoycoKernel
    function jtConvertTrancheUnitsToNAVUnits(TRANCHE_UNIT _jtAssets) public view override(RoycoKernel) returns (NAV_UNIT nav) {
        return toNAVUnits(toUint256(_jtAssets) * getTrancheUnitToNAVUnitConversionRate() / WAD);
    }

    /// @inheritdoc RoycoKernel
    function stConvertNAVUnitsToTrancheUnits(NAV_UNIT _nav) public view override(RoycoKernel) returns (TRANCHE_UNIT stAssets) {
        return toTrancheUnits(toUint256(_nav) * WAD / getTrancheUnitToNAVUnitConversionRate());
    }

    /// @inheritdoc RoycoKernel
    function jtConvertNAVUnitsToTrancheUnits(NAV_UNIT _nav) public view override(RoycoKernel) returns (TRANCHE_UNIT jtAssets) {
        return toTrancheUnits(toUint256(_nav) * WAD / getTrancheUnitToNAVUnitConversionRate());
    }

    /// @notice Returns the tranche unit to NAV unit conversion rate
    /// @dev If the override is set, it will return the override value, otherwise it will return the value queried from the oracle
    /// @return ratetrancheUnitToNAVUnitConversionRateWAD The tranche unit to NAV unit conversion rate
    function getTrancheUnitToNAVUnitConversionRate() public view returns (uint256 ratetrancheUnitToNAVUnitConversionRateWAD) {
        OverridableNAVOracleIdenticalAssetsQuoterState storage $ = _getOverridableNAVOracleIdenticalAssetsQuoterStorage();
        ratetrancheUnitToNAVUnitConversionRateWAD = $.ratetrancheUnitToNAVUnitConversionRateWAD;
        if (ratetrancheUnitToNAVUnitConversionRateWAD != 0) {
            return ratetrancheUnitToNAVUnitConversionRateWAD;
        }

        return _getTrancheUnitToNAVUnitConversionRate();
    }

    /// @notice Returns the tranche unit to NAV unit conversion rate
    /// @dev This function is overridden by the child contract to return the value queried from the oracle
    /// @dev This must have the same precision as $.ratetrancheUnitToNAVUnitConversionRateWAD, which is WAD precision
    /// @return ratetrancheUnitToNAVUnitConversionRateWAD The tranche unit to NAV unit conversion rate
    function _getTrancheUnitToNAVUnitConversionRate() internal view virtual returns (uint256 ratetrancheUnitToNAVUnitConversionRateWAD);

    /**
     * @notice Returns a storage pointer to the OverridableNAVOracleIdenticalAssetsQuoterState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer
     */
    function _getOverridableNAVOracleIdenticalAssetsQuoterStorage() internal pure returns (OverridableNAVOracleIdenticalAssetsQuoterState storage $) {
        assembly ("memory-safe") {
            $.slot := OVERRIDABLE_NAV_ORACLE_IDENTICAL_ASSETS_QUOTER_STORAGE_SLOT
        }
    }
}
