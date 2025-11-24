// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC165 } from "../../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import { IERC7540 } from "./IERC7540.sol";
import { IERC7575 } from "./IERC7575.sol";
import { IERC7887 } from "./IERC7887.sol";

interface IRoycoTranche is IERC165, IERC7540, IERC7575, IERC7887 {
    /// @notice Returns the net asset value controlled by the tranche
    /// @dev The NAV is expressed in the tranche's base asset
    function getNAV() external view returns (uint256);
}

interface IRoycoSeniorTranche {
    /// @notice Returns the total principal assets deployed into the senior tranche
    /// @dev The principal is expressed in the tranches base asset
    function getTotalPrincipalAssets() external view returns (uint256);
}
