// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ERC4626Upgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ErrorsLib } from "../libraries/ErrorsLib.sol";

// TODO: Override the ERC4626 _deposit, _burn and _transfer function directly to update the cost basis ledger
// instead of using the internal functions
abstract contract CostBasisLedger is ERC4626Upgradeable {
    // keccak256(abi.encode(uint256(keccak256("Royco.storage.CostBasisLedgerStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COST_BASIS_LEDGER_STORAGE_SLOT = 0x317a176495792a1d1e1aa15eedc89ec3b8f6f16933936e6f981fa3fd42a86e00;

    /// @custom:storage-location erc7201:Royco.storage.CostBasisLedgerStorage
    struct CostBasisLedgerStorage {
        mapping(address user => uint256 costBasisOfSharesOwned) userToCostBasisOfSharesOwned;
        uint256 totalCostBasis;
    }

    function totalCostBasis() public view returns (uint256) {
        CostBasisLedgerStorage storage $ = _getCostBasisLedgerStorage();
        return $.totalCostBasis;
    }

    function _updateCostBasisOnDeposit(address _user, uint256 _assetsDeposited) internal {
        CostBasisLedgerStorage storage $ = _getCostBasisLedgerStorage();
        $.userToCostBasisOfSharesOwned[_user] += _assetsDeposited;
        $.totalCostBasis += _assetsDeposited;
    }

    function _updateCostBasisOnRedeem(address _user, uint256 _totalSharesOwned, uint256 _totalSharesRedeemed) internal {
        require(_totalSharesRedeemed <= _totalSharesOwned, ErrorsLib.CANNOT_REDEEM_MORE_THAN_OWNED());

        CostBasisLedgerStorage storage $ = _getCostBasisLedgerStorage();

        uint256 totalCostBasisOwnedByUser = $.userToCostBasisOfSharesOwned[_user];
        // TODO: Justfiy rounding direction
        uint256 costBasisForSharesRedeemed = Math.mulDiv(totalCostBasisOwnedByUser, _totalSharesRedeemed, _totalSharesOwned, Math.Rounding.Floor);

        unchecked {
            $.userToCostBasisOfSharesOwned[_user] -= costBasisForSharesRedeemed;
            $.totalCostBasis -= costBasisForSharesRedeemed;
        }
    }

    /// @dev Override the ERC20 _update function to update the cost basis ledger
    function _update(address _from, address _to, uint256 _amount) internal virtual override {
        // If the transfer is not from the zero address to the zero address, it is a transfer between users
        if (_from != address(0) && _to != address(0)) {
            CostBasisLedgerStorage storage $ = _getCostBasisLedgerStorage();

            // TODO: Justfiy rounding direction
            uint256 costBasisForSharesTransferred = Math.mulDiv($.userToCostBasisOfSharesOwned[_from], _amount, balanceOf(_from), Math.Rounding.Floor);

            unchecked {
                $.userToCostBasisOfSharesOwned[_from] -= costBasisForSharesTransferred;
            }
            $.userToCostBasisOfSharesOwned[_to] += costBasisForSharesTransferred;
        }

        super._update(_from, _to, _amount);
    }

    function _getCostBasisLedgerStorage() private pure returns (CostBasisLedgerStorage storage $) {
        assembly ("memory-safe") {
            $.slot := COST_BASIS_LEDGER_STORAGE_SLOT
        }
    }
}
