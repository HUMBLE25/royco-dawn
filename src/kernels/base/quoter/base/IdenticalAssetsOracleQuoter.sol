// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RAY } from "../../../../libraries/Constants.sol";
import { Math, NAV_UNIT, TRANCHE_UNIT, UnitsMathLib, toNAVUnits, toTrancheUnits, toUint256 } from "../../../../libraries/Units.sol";
import { RoycoKernel } from "../../RoycoKernel.sol";

/**
 * @title IdenticalAssetsOracleQuoter
 * @notice Quoter to convert tranche units to/from NAV units using an oracle for markets where both tranches use the same tranche units
 * @dev The quoter reads the conversion rate from the specified oracle in RAY precision.
 *      The kernel admin can optionally override the conversion rate with a fixed value.
 *      Supported use-cases include:
 *      - Identical Yield Bearing ERC20 for ST And JT: Yield Bearing ERC20 and Tranche Unit (sACRED, reUSD, etc.), NAV Unit (USD)
 */
// TODO: Cache conversion rate initially
abstract contract IdenticalAssetsOracleQuoter is RoycoKernel {
    using UnitsMathLib for NAV_UNIT;
    using UnitsMathLib for TRANCHE_UNIT;

    /// @dev Storage slot for IdenticalAssetsOracleQuoterState using ERC-7201 pattern
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.IdenticalAssetsOracleQuoterState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant IDENTICAL_ASSETS_ORACLE_QUOTER_STORAGE_SLOT = 0xca94f7ca84d231255275e1b9f26a7020d13b86fcd22e881d1138f23eeb47cf00;

    /// @notice A sentinel value for the conversion rate, indicating that the conversion rate should be queried in real time from the specified oracle
    uint256 internal constant SENTINEL_CONVERSION_RATE = 0;

    /// @dev Storage state for the Royco identical assets overridable oracle quoter
    /// @custom:storage-location erc7201:Royco.storage.IdenticalAssetsOracleQuoterState
    struct IdenticalAssetsOracleQuoterState {
        uint256 conversionRateRAY;
    }

    /// @notice Emitted when the tranche unit to NAV unit conversion rate is updated
    /// @param _conversionRateRAY The updated conversion rate as defined by the oracle, scaled to RAY precision
    event ConversionRateUpdated(uint256 _conversionRateRAY);

    /// @notice Thrown when the senior and junior tranche assets are not identical
    error TRANCHE_ASSETS_MUST_BE_IDENTICAL();

    /**
     * @notice Initializes the identical assets oracle quoter
     * @param _initialConversionRateRAY The initial conversion rate as defined by the oracle, scaled to RAY precision
     */
    function __IdenticalAssetsOracleQuoter_init_unchained(uint256 _initialConversionRateRAY) internal onlyInitializing {
        // The tranche units must be identical for both tranches since their is a single conversion rate
        require(ST_ASSET == JT_ASSET, TRANCHE_ASSETS_MUST_BE_IDENTICAL());

        // Premptively return if this quoter is reliant on an oracle instead of an admin set conversion rate
        if (_initialConversionRateRAY == SENTINEL_CONVERSION_RATE) return;
        _getIdenticalAssetsOracleQuoterStorage().conversionRateRAY = _initialConversionRateRAY;
        emit ConversionRateUpdated(_initialConversionRateRAY);
    }

    /// @inheritdoc RoycoKernel
    function stConvertTrancheUnitsToNAVUnits(TRANCHE_UNIT _stAssets) public view override(RoycoKernel) returns (NAV_UNIT nav) {
        return _convertTrancheUnitsToNAVUnits(_stAssets);
    }

    /// @inheritdoc RoycoKernel
    function jtConvertTrancheUnitsToNAVUnits(TRANCHE_UNIT _jtAssets) public view override(RoycoKernel) returns (NAV_UNIT nav) {
        return _convertTrancheUnitsToNAVUnits(_jtAssets);
    }

    /// @inheritdoc RoycoKernel
    function stConvertNAVUnitsToTrancheUnits(NAV_UNIT _nav) public view override(RoycoKernel) returns (TRANCHE_UNIT stAssets) {
        return _convertNAVUnitsToTrancheUnits(_nav);
    }

    /// @inheritdoc RoycoKernel
    function jtConvertNAVUnitsToTrancheUnits(NAV_UNIT _nav) public view override(RoycoKernel) returns (TRANCHE_UNIT jtAssets) {
        return _convertNAVUnitsToTrancheUnits(_nav);
    }

    /**
     * @notice Sets the tranche unit to NAV unit conversion rate
     * @dev Once this is set, the quoter will rely solely on this value instead of
     * @dev Only callable by a designated admin
     * @param _conversionRateRAY The conversion rate as defined by the oracle, scaled to RAY precision
     */
    function setConversionRate(uint256 _conversionRateRAY) public virtual restricted {
        _getIdenticalAssetsOracleQuoterStorage().conversionRateRAY = _conversionRateRAY;
        emit ConversionRateUpdated(_conversionRateRAY);
    }

    /// @notice Returns the value of 1 Tranche Unit in NAV Units, scaled to RAY precision
    /// @dev If the override is set, it will return the override value, otherwise it will return the value queried from the oracle
    /// @return trancheToNAVUnitConversionRateRAY The tranche unit to NAV unit conversion rate
    function getTrancheUnitToNAVUnitConversionRate() public view virtual returns (uint256 trancheToNAVUnitConversionRateRAY) {
        // If there is an admin set conversion rate, use that, else query the oracle for the rate
        trancheToNAVUnitConversionRateRAY = getStoredConversionRateRAY();
        if (trancheToNAVUnitConversionRateRAY != SENTINEL_CONVERSION_RATE) return trancheToNAVUnitConversionRateRAY;
        return _getConversionRateFromOracle();
    }

    /// @notice Returns the stored conversion rate, scaled to RAY precision
    /// @return conversionRateRAY The stored conversion rate, scaled to RAY precision
    function getStoredConversionRateRAY() public view returns (uint256) {
        return _getIdenticalAssetsOracleQuoterStorage().conversionRateRAY;
    }

    /**
     * @notice Returns the tranche unit to NAV unit conversion rate, scaled to RAY precision
     * @dev This function should be overridden if the conversion rate needs to be fetched from an oracle
     * @return conversionRateRAY The conversion rate from tranche units to NAV units, scaled to RAY precision
     */
    function _getConversionRateFromOracle() internal view virtual returns (uint256 conversionRateRAY);

    /// @dev Converts tranche units to NAV units for both tranches since they use identical assets
    function _convertTrancheUnitsToNAVUnits(TRANCHE_UNIT _assets) internal view returns (NAV_UNIT) {
        return toNAVUnits(toUint256(_assets.mulDiv(getTrancheUnitToNAVUnitConversionRate(), RAY, Math.Rounding.Floor)));
    }

    /// @dev Converts NAV units to tranche units for both tranches since they use identical assets
    function _convertNAVUnitsToTrancheUnits(NAV_UNIT _nav) internal view returns (TRANCHE_UNIT) {
        return toTrancheUnits(toUint256(_nav.mulDiv(RAY, getTrancheUnitToNAVUnitConversionRate(), Math.Rounding.Floor)));
    }

    /**
     * @notice Returns a storage pointer to the IdenticalAssetsOracleQuoterState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer
     */
    function _getIdenticalAssetsOracleQuoterStorage() private pure returns (IdenticalAssetsOracleQuoterState storage $) {
        assembly ("memory-safe") {
            $.slot := IDENTICAL_ASSETS_ORACLE_QUOTER_STORAGE_SLOT
        }
    }
}
