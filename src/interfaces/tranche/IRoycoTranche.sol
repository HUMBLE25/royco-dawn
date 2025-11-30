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

interface IRoycoJuniorTranche {
    /**
     * @notice Called the senior tranche when the junior tranche needs to cover a loss for a withdrawing senior tranche depositor
     * @param _assets The loss to cover in the junior tranche's base asset
     * @param _receiver The receiver of the loss payout
     * @return The request ID if the junior tranche employs an asynchronous withdrawal model
     */
    function coverLosses(uint256 _assets, address _receiver) external returns (uint256);
}
