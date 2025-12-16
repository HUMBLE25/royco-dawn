// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @dev The unit of measurement for NAV values
/// @dev This unit is expected to expressed in the same asset (USD, EUR, BTC, etc) and precision (RAY, WAD, etc.) for the ST and JT tranches of a Royco market
type NAV_UNIT is uint256;

/// @dev The unit of measurement for tranche assets
type TRANCHE_UNIT is uint256;

/// @title UnitsMathLib
/// @notice Math library wrapper for Royco's units of measurement
library UnitsMathLib {
    /**
     * @notice Computes the minimum of two NAV unit denominated quantities
     * @param _a A NAV unit denominated quantity
     * @param _b A NAV unit denominated quantity
     * @return The minimum of _a and _b in NAV units
     */
    function min(NAV_UNIT _a, NAV_UNIT _b) internal pure returns (NAV_UNIT) {
        return toNAVUnits(Math.min(toUint256(_a), toUint256(_b)));
    }

    /**
     * @notice Computes the signed delta between two NAV unit denominated quantities
     * @param _a The NAV unit denominated minuend of the subtraction
     * @param _b The NAV unit denominated subtrahend of the subtraction
     * @return The signed difference between _a and _b
     */
    function computeNAVDelta(NAV_UNIT _a, NAV_UNIT _b) internal pure returns (int256) {
        return (int256(toUint256(_a)) - int256(toUint256(_b)));
    }

    /**
     * @notice Computes the difference between two NAV unit denominated quantities, clipped to 0
     * @param _a The NAV unit denominated minuend of the subtraction
     * @param _b The NAV unit denominated subtrahend of the subtraction
     * @return The difference between _a and _b, clipped to 0
     */
    function saturatingSub(NAV_UNIT _a, NAV_UNIT _b) internal pure returns (NAV_UNIT) {
        return toNAVUnits(Math.saturatingSub(toUint256(_a), toUint256(_b)));
    }

    /**
     * @notice Multiplies two NAV unit denominated quantities and divides by a third NAV unit denominated quantity, rounding according to the specified rounding mode
     * @param _a The NAV unit denominated multiplicand of the multiplication
     * @param _b The NAV unit denominated multiplier of the multiplication
     * @param _c The NAV unit denominated divisor of the division
     * @param _rounding The rounding mode to use
     * @return The result of the multiplication followed by division
     */
    function mulDiv(NAV_UNIT _a, NAV_UNIT _b, NAV_UNIT _c, Math.Rounding _rounding) internal pure returns (NAV_UNIT) {
        return toNAVUnits(Math.mulDiv(toUint256(_a), toUint256(_b), toUint256(_c), _rounding));
    }

    /**
     * @notice Multiplies a NAV unit denominated quantity by a uint256 and divides by another uint256, rounding according to the specified rounding mode
     * @param _a The NAV unit denominated multiplicand of the multiplication
     * @param _b The uint256 multiplier of the multiplication
     * @param _c The uint256 divisor of the division
     * @param _rounding The rounding mode to use
     * @return The result of the multiplication followed by division
     */
    function mulDiv(NAV_UNIT _a, uint256 _b, uint256 _c, Math.Rounding _rounding) internal pure returns (NAV_UNIT) {
        return toNAVUnits(Math.mulDiv(toUint256(_a), _b, _c, _rounding));
    }

    /**
     * @notice Multiplies a NAV unit denominated quantity by a uint256 and divides by another NAV unit denominated quantity, rounding according to the specified rounding mode
     * @param _a The NAV unit denominated multiplicand of the multiplication
     * @param _b The uint256 multiplier of the multiplication
     * @param _c The NAV unit denominated divisor of the division
     * @param _rounding The rounding mode to use
     * @return The result of the multiplication followed by division
     */
    function mulDiv(NAV_UNIT _a, uint256 _b, NAV_UNIT _c, Math.Rounding _rounding) internal pure returns (NAV_UNIT) {
        return toNAVUnits(Math.mulDiv(toUint256(_a), _b, toUint256(_c), _rounding));
    }

    /**
     * @notice Multiplies two tranche unit denominated quantities and divides by a third tranche unit denominated quantity, rounding according to the specified rounding mode
     * @param _a The first tranche unit denominated quantity
     * @param _b The second tranche unit denominated quantity
     * @param _c The third tranche unit denominated quantity
     * @param _rounding The rounding mode to use
     * @return The result of the multiplication followed by division
     */
    function mulDiv(TRANCHE_UNIT _a, TRANCHE_UNIT _b, TRANCHE_UNIT _c, Math.Rounding _rounding) internal pure returns (TRANCHE_UNIT) {
        return toTrancheUnits(Math.mulDiv(toUint256(_a), toUint256(_b), toUint256(_c), _rounding));
    }
}

/// ----------------------
/// NAV_UNIT Helpers
/// ----------------------

function toNAVUnits(uint256 _assets) pure returns (NAV_UNIT) {
    return NAV_UNIT.wrap(_assets);
}

function toNAVUnits(int256 _assets) pure returns (NAV_UNIT) {
    return NAV_UNIT.wrap(uint256(_assets));
}

function toUint256(NAV_UNIT _units) pure returns (uint256) {
    return NAV_UNIT.unwrap(_units);
}

function addNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (NAV_UNIT) {
    return NAV_UNIT.wrap(NAV_UNIT.unwrap(_a) + NAV_UNIT.unwrap(_b));
}

function subNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (NAV_UNIT) {
    return NAV_UNIT.wrap(NAV_UNIT.unwrap(_a) - NAV_UNIT.unwrap(_b));
}

function mulNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (NAV_UNIT) {
    return NAV_UNIT.wrap(NAV_UNIT.unwrap(_a) * NAV_UNIT.unwrap(_b));
}

function divNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (NAV_UNIT) {
    return NAV_UNIT.wrap(NAV_UNIT.unwrap(_a) / NAV_UNIT.unwrap(_b));
}

function lessThanNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (bool) {
    return NAV_UNIT.unwrap(_a) < NAV_UNIT.unwrap(_b);
}

function lessThanOrEqualToNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (bool) {
    return NAV_UNIT.unwrap(_a) <= NAV_UNIT.unwrap(_b);
}

function greaterThanNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (bool) {
    return NAV_UNIT.unwrap(_a) > NAV_UNIT.unwrap(_b);
}

function greaterThanOrEqualToNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (bool) {
    return NAV_UNIT.unwrap(_a) >= NAV_UNIT.unwrap(_b);
}

function equalsNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (bool) {
    return NAV_UNIT.unwrap(_a) == NAV_UNIT.unwrap(_b);
}

function notEqualsNAVUnits(NAV_UNIT _a, NAV_UNIT _b) pure returns (bool) {
    return NAV_UNIT.unwrap(_a) != NAV_UNIT.unwrap(_b);
}

using {
    addNAVUnits as +,
    subNAVUnits as -,
    mulNAVUnits as *,
    divNAVUnits as /,
    lessThanNAVUnits as <,
    lessThanOrEqualToNAVUnits as <=,
    greaterThanNAVUnits as >,
    greaterThanOrEqualToNAVUnits as >=,
    equalsNAVUnits as ==,
    notEqualsNAVUnits as !=
} for NAV_UNIT global;

/// ----------------------
/// TRANCHE_UNIT Helpers
/// ----------------------

function toTrancheUnits(uint256 _assets) pure returns (TRANCHE_UNIT) {
    return TRANCHE_UNIT.wrap(_assets);
}

function toUint256(TRANCHE_UNIT _units) pure returns (uint256) {
    return TRANCHE_UNIT.unwrap(_units);
}

function addTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (TRANCHE_UNIT) {
    return TRANCHE_UNIT.wrap(TRANCHE_UNIT.unwrap(_a) + TRANCHE_UNIT.unwrap(_b));
}

function subTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (TRANCHE_UNIT) {
    return TRANCHE_UNIT.wrap(TRANCHE_UNIT.unwrap(_a) - TRANCHE_UNIT.unwrap(_b));
}

function mulTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (TRANCHE_UNIT) {
    return TRANCHE_UNIT.wrap(TRANCHE_UNIT.unwrap(_a) * TRANCHE_UNIT.unwrap(_b));
}

function divTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (TRANCHE_UNIT) {
    return TRANCHE_UNIT.wrap(TRANCHE_UNIT.unwrap(_a) / TRANCHE_UNIT.unwrap(_b));
}

function lessThanTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (bool) {
    return TRANCHE_UNIT.unwrap(_a) < TRANCHE_UNIT.unwrap(_b);
}

function lessThanOrEqualToTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (bool) {
    return TRANCHE_UNIT.unwrap(_a) <= TRANCHE_UNIT.unwrap(_b);
}

function greaterThanTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (bool) {
    return TRANCHE_UNIT.unwrap(_a) > TRANCHE_UNIT.unwrap(_b);
}

function greaterThanOrEqualToTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (bool) {
    return TRANCHE_UNIT.unwrap(_a) >= TRANCHE_UNIT.unwrap(_b);
}

function equalsTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (bool) {
    return TRANCHE_UNIT.unwrap(_a) == TRANCHE_UNIT.unwrap(_b);
}

function notEqualsTrancheUnits(TRANCHE_UNIT _a, TRANCHE_UNIT _b) pure returns (bool) {
    return TRANCHE_UNIT.unwrap(_a) != TRANCHE_UNIT.unwrap(_b);
}

using {
    addTrancheUnits as +,
    subTrancheUnits as -,
    mulTrancheUnits as *,
    divTrancheUnits as /,
    lessThanTrancheUnits as <,
    lessThanOrEqualToTrancheUnits as <=,
    greaterThanTrancheUnits as >,
    greaterThanOrEqualToTrancheUnits as >=,
    equalsTrancheUnits as ==,
    notEqualsTrancheUnits as !=
} for TRANCHE_UNIT global;
