// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "../../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import { AssetClaims } from "../../libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT } from "../../libraries/Units.sol";
import { IRoycoAsyncCancellableVault } from "./IRoycoAsyncCancellableVault.sol";
import { IRoycoAsyncVault } from "./IRoycoAsyncVault.sol";

/**
 * @title IRoycoVaultTranche
 * @notice Interface for Royco tranches that implement the asynchronous deposit and redemption flows
 */
interface IRoycoVaultTranche is IERC165, IERC20, IRoycoAsyncVault, IRoycoAsyncCancellableVault {
    /**
     * @notice Mints tranche shares to the protocol fee recipient, representing ownership over the fee assets of the tranche
     * @dev Must be called by the tranche's kernel everytime protocol fees are accrued in its pre-op synchronization
     * @param _protocolFeeAssets The fee accrued for this tranche as a result of the pre-op sync
     * @param _protocolFeeRecipient The address to receive the freshly minted protocol fee shares
     * @param _trancheTotalAssets The total effective assets controlled by this tranche as a result of the pre-op sync
     * @return totalSharesIncludingVirtualShares The total number of shares that will be minted to the protocol fee recipient, including virtual shares
     */
    function mintProtocolFeeShares(
        NAV_UNIT _protocolFeeAssets,
        NAV_UNIT _trancheTotalAssets,
        address _protocolFeeRecipient
    )
        external
        returns (uint256 totalSharesIncludingVirtualShares);

    /**
     * @notice Returns the address of the kernel contract handling strategy logic
     */
    function kernel() external view returns (address);

    /**
     * @notice Returns the identifier of the Royco market this tranche is linked to
     */
    function marketId() external view returns (bytes32);

    /**
     * @notice Returns the address of the tranche's deposit asset
     * @return asset The address of the tranche's deposit asset
     */
    function asset() external view returns (address asset);

    /**
     * @notice Returns the raw net asset value of the tranche's invested assets
     * @dev Excludes yield splits, coverage applications, etc.
     * @dev The NAV is expressed in the tranche's base asset
     * @return nav The raw net asset value of the tranche's invested assets
     */
    function getRawNAV() external view returns (NAV_UNIT nav);

    /**
     * @notice Returns the total effective assets in the tranche's NAV units
     * @dev Includes yield splits, coverage applications, etc.
     * @dev The NAV is expressed in the tranche's base asset
     * @return claims The breakdown of assets that represent the value of the tranche's shares
     */
    function totalAssets() external view returns (AssetClaims memory claims);

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the tranche
     * @dev The assets are expressed in the tranche's base asset
     * @param _receiver The address to receive the deposited assets
     * @return assets The maximum amount of assets in the tranche's base asset that can be deposited into the tranche
     */
    function maxDeposit(address _receiver) external view returns (TRANCHE_UNIT assets);

    /**
     * @notice Returns the number of shares that would be minted for a given amount of assets
     * @dev The assets are expressed in the tranche's base asset
     * @param _assets The amount of assets to preview the deposit for
     * @return shares The number of shares that would be minted for a given amount of assets
     */
    function previewDeposit(TRANCHE_UNIT _assets) external view returns (uint256 shares);

    /**
     * @notice Returns the number of shares that would be minted for a given amount of assets
     * @dev The assets are expressed in the tranche's base asset
     * @param _assets The amount of assets to convert to shares
     * @return shares The number of shares that would be minted for a given amount of assets
     */
    function convertToShares(TRANCHE_UNIT _assets) external view returns (uint256 shares);

    /**
     * @notice Returns the maximum amount of shares that can be redeemed from the tranche
     * @dev The shares are expressed in the tranche's base asset
     * @param _owner The address to redeem the shares from
     * @return shares The maximum amount of shares that can be redeemed from the tranche
     */
    function maxRedeem(address _owner) external view returns (uint256 shares);

    /**
     * @notice Returns the breakdown of assets that the shares have a claim on
     * @dev The shares are expressed in the tranche's base asset
     * @param _shares The number of shares to convert to claims
     * @return claims The breakdown of assets that the shares have a claim on
     */
    function previewRedeem(uint256 _shares) external view returns (AssetClaims memory claims);

    /**
     * @notice Returns the breakdown of assets that the shares have a claim on
     * @dev The shares are expressed in the tranche's base asset
     * @param _shares The number of shares to convert to assets
     * @return claims The breakdown of assets that the shares have a claim on
     */
    function convertToAssets(uint256 _shares) external view returns (AssetClaims memory claims);
}
