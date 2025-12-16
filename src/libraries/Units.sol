// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @dev The unit of measurement for NAV values
type NAV_UNIT is uint256;

/// @dev The unit of measurement for tranche assets
type TRANCHE_UNIT is uint256;

/// @title UnitsMath
/// @notice Math library wrapper for units of measurement
library UnitsMath {
    /// @notice Multiplies two NAV units and divides by a third NAV unit, rounding according to the specified rounding mode
    /// @param _a The first NAV unit
    /// @param _b The second NAV unit
    /// @param _c The third NAV unit
    /// @param _rounding The rounding mode to use
    /// @return The result of the multiplication and division
    function mulDiv(NAV_UNIT _a, NAV_UNIT _b, NAV_UNIT _c, Math.Rounding _rounding) internal pure returns (NAV_UNIT) {
        return NAV_UNIT.wrap(Math.mulDiv(NAV_UNIT.unwrap(_a), NAV_UNIT.unwrap(_b), NAV_UNIT.unwrap(_c), _rounding));
    }

    /// @notice Multiplies two tranche units and divides by a third tranche unit, rounding according to the specified rounding mode
    /// @param _a The first tranche unit
    /// @param _b The second tranche unit
    /// @param _c The third tranche unit
    /// @param _rounding The rounding mode to use
    /// @return The result of the multiplication and division
    function mulDiv(TRANCHE_UNIT _a, TRANCHE_UNIT _b, TRANCHE_UNIT _c, Math.Rounding _rounding) internal pure returns (TRANCHE_UNIT) {
        return TRANCHE_UNIT.wrap(Math.mulDiv(TRANCHE_UNIT.unwrap(_a), TRANCHE_UNIT.unwrap(_b), TRANCHE_UNIT.unwrap(_c), _rounding));
    }
}

/// ----------------------
/// NAV_UNIT Helpers
/// ----------------------

function toNAVUnits(uint256 _assets) pure returns (NAV_UNIT) {
    return NAV_UNIT.wrap(_assets);
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
