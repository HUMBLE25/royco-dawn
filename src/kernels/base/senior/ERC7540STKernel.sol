// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { BaseKernelState, BaseKernelStorageLib } from "../../../libraries/BaseKernelStorageLib.sol";
import { ConstantsLib } from "../../../libraries/ConstantsLib.sol";
import { BaseKernel, IBaseKernel } from "../BaseKernel.sol";

abstract contract AaveV3JTKernel is BaseKernel { }
