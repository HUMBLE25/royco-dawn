// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from "../../../lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import { ERC20Upgradeable } from "../../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata,
    IERC4626,
    Math
} from "../../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC7540 } from "../../interfaces/IERC7540.sol";
import { IERC7575 } from "../../interfaces/IERC7575.sol";
import { IERC165, IERC7887 } from "../../interfaces/IERC7887.sol";
import { ConstantsLib } from "../../libraries/ConstantsLib.sol";

import { RoycoJTStorageLib } from "../../libraries/RoycoJTStorageLib.sol";
import { ExecutionModel, RoycoKernelLib } from "../../libraries/RoycoKernelLib.sol";
import { TrancheDeploymentParams } from "../../libraries/Types.sol";

contract RoycoJT is Ownable2StepUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    function initialize(
        TrancheDeploymentParams calldata _jtParams,
        address _asset,
        address _owner,
        uint64 _rewardFeeWAD,
        address _feeClaimant,
        address _rdm,
        uint64 _coverageWAD,
        address _seniorTranche
    )
        external
        initializer
    {
        // Initialize the parent contracts
        __ERC20_init_unchained(_jtParams.name, _jtParams.symbol);
        __ERC4626_init_unchained(IERC20(_asset));
        __Ownable_init_unchained(_owner);

        // Calculate the vault's decimal offset (curb inflation attacks)
        uint8 underlyingAssetDecimals = IERC20Metadata(_asset).decimals();
        uint8 decimalsOffset = underlyingAssetDecimals >= 18 ? 0 : (18 - underlyingAssetDecimals);

        // Initialize the senior tranche state
        RoycoJTStorageLib.__RoycoJT_init(msg.sender, _jtParams.kernel, _rewardFeeWAD, _feeClaimant, _coverageWAD, _seniorTranche, decimalsOffset);

        // Initialize the kernel's state
        RoycoKernelLib.__Kernel_init(RoycoJTStorageLib._getKernel(), _jtParams.kernelInitParams);
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return RoycoJTStorageLib._getDecimalsOffset();
    }
}
