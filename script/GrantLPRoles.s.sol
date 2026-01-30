// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "../lib/openzeppelin-contracts/contracts/access/manager/IAccessManager.sol";
import { RolesConfiguration } from "../src/factory/RolesConfiguration.sol";
import { Script } from "lib/forge-std/src/Script.sol";
import { console2 } from "lib/forge-std/src/console2.sol";

/**
 * @title GrantLPRolesScript
 * @author Ankur Dubey, Shivaansh Kapoor
 * @notice Script for granting LP roles to addresses
 * @dev This script reads from environment variables to grant LP roles to a list of addresses
 */
contract GrantLPRolesScript is Script, RolesConfiguration {
    /// @notice Error when no addresses are provided
    error NoAddressesProvided();

    /// @notice Error when factory address is not set
    error FactoryAddressNotSet();

    /**
     * @notice Main entry point - reads addresses from environment and grants LP roles
     * @dev Reads FACTORY_ADDRESS and LP_ADDRESSES (comma-separated) from environment
     *      Uses Foundry's vm.envAddress(key, delimiter) to parse the address list
     */
    function run() external {
        // Read factory address from environment
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        if (factoryAddress == address(0)) {
            revert FactoryAddressNotSet();
        }

        // Read LP addresses from environment using Foundry's built-in delimiter parsing
        // LP_ADDRESSES should be comma-separated: "0x123...,0x456...,0x789..."
        address[] memory lpAddresses = vm.envAddress("LP_ADDRESSES", ",");

        if (lpAddresses.length == 0) {
            revert NoAddressesProvided();
        }

        // Read deployer private key and broadcast
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        grantLPRoles(factoryAddress, lpAddresses, privateKey);
    }

    /**
     * @notice Grants LP role to a list of addresses with broadcast
     * @param _factory The factory/access manager address
     * @param _addresses The addresses to grant LP role to
     * @param _privateKey The private key to broadcast with
     */
    function grantLPRoles(address _factory, address[] memory _addresses, uint256 _privateKey) public {
        vm.startBroadcast(_privateKey);

        IAccessManager accessManager = IAccessManager(_factory);

        console2.log("Granting LP roles on AccessManager:", _factory);
        console2.log("Number of addresses:", _addresses.length);

        for (uint256 i = 0; i < _addresses.length; i++) {
            address addr = _addresses[i];
            if (addr == address(0)) {
                console2.log("  - Skipping zero address at index:", i);
                continue;
            }

            (bool hasRole,) = accessManager.hasRole(LP_ROLE, addr);
            if (!hasRole) {
                accessManager.grantRole(LP_ROLE, addr, 0);
                console2.log("  - Granted LP_ROLE to:", addr);
            } else {
                console2.log("  - LP_ROLE already granted to:", addr);
            }
        }

        console2.log("LP roles granted successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Revokes LP role from a list of addresses with broadcast
     * @param _factory The factory/access manager address
     * @param _addresses The addresses to revoke LP role from
     * @param _privateKey The private key to broadcast with
     */
    function revokeLPRoles(address _factory, address[] memory _addresses, uint256 _privateKey) public {
        vm.startBroadcast(_privateKey);

        IAccessManager accessManager = IAccessManager(_factory);

        console2.log("Revoking LP roles on AccessManager:", _factory);
        console2.log("Number of addresses:", _addresses.length);

        for (uint256 i = 0; i < _addresses.length; i++) {
            address addr = _addresses[i];
            if (addr == address(0)) {
                console2.log("  - Skipping zero address at index:", i);
                continue;
            }

            (bool hasRole,) = accessManager.hasRole(LP_ROLE, addr);
            if (hasRole) {
                accessManager.revokeRole(LP_ROLE, addr);
                console2.log("  - Revoked LP_ROLE from:", addr);
            } else {
                console2.log("  - LP_ROLE not granted to:", addr);
            }
        }

        console2.log("LP roles revoked successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Revokes LP role from a single address with broadcast
     * @param _factory The factory/access manager address
     * @param _address The address to revoke LP role from
     * @param _privateKey The private key to broadcast with
     */
    function revokeLPRole(address _factory, address _address, uint256 _privateKey) public {
        address[] memory addresses = new address[](1);
        addresses[0] = _address;
        revokeLPRoles(_factory, addresses, _privateKey);
    }
}
