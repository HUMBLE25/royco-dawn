// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { RoycoAuth } from "../auth/RoycoAuth.sol";

/**
 * @title RoycoBase
 * @notice Abstract contract that provides the base functionality for Royco contracts
 * @dev This contract is used to inherit from other Royco contracts to provide the base functionality
 *      such as access control and restricted upgradeability
 */
abstract contract RoycoBase is UUPSUpgradeable, RoycoAuth {
    /**
     * @dev Disable the initializers
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Royco base contract
     * @param _initialAuthority The initial authority for the contract
     */
    function __RoycoBase_init(address _initialAuthority) internal onlyInitializing {
        __RoycoAuth_init(_initialAuthority);
    }

    /**
     * @dev Restricts the upgrade to only the authorized roles
     */
    function _authorizeUpgrade(address newImplementation) internal override restricted { }
}
