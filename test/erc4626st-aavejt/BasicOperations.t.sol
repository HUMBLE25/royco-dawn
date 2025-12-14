// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { MainnetForkWithAaveTestBase } from "./base/MainnetForkWithAaveBaseTest.sol";

contract BasicOperationsTest is MainnetForkWithAaveTestBase {
    IERC20 internal usdc = IERC20(ETHEREUM_MAINNET_USDC_ADDRESS);
    IERC20 internal aToken = IERC20(aTokenAddresses[1][ETHEREUM_MAINNET_USDC_ADDRESS]);

    function setUp() public {
        _setUpRoyco();
        _setUpTrancheRoles(address(juniorTranche), providers, PAUSER_ADDRESS, UPGRADER_ADDRESS, SCHEDULER_MANAGER_ADDRESS);
    }

    /// @notice Fuzz test: deposit into junior tranche
    /// @param _assets Amount of assets to deposit (fuzzed)
    function testFuzz_depositIntoJT(uint256 _assets) public {
        // Bound assets to reasonable range (avoid zero and very large amounts)
        _assets = bound(_assets, 1e6, 1_000_000e6); // Between 1 USDC and 1M USDC (6 decimals)

        address depositor = ALICE_ADDRESS;

        // Get initial balances
        uint256 initialDepositorBalance = usdc.balanceOf(depositor);
        uint256 initialTrancheShares = juniorTranche.balanceOf(depositor);
        uint256 initialTrancheTotalSupply = juniorTranche.totalSupply();

        // Approve the junior tranche to spend assets
        vm.prank(depositor);
        usdc.approve(address(juniorTranche), _assets);

        // Deposit into junior tranche
        vm.prank(depositor);
        uint256 shares = juniorTranche.deposit(_assets, depositor, depositor);

        // Verify shares were minted
        assertGt(shares, 0, "Shares should be greater than 0");
        assertEq(juniorTranche.balanceOf(depositor), initialTrancheShares + shares, "Depositor should receive shares");
        assertEq(juniorTranche.totalSupply(), initialTrancheTotalSupply + shares, "Total supply should increase");

        // Verify assets were transferred
        assertEq(usdc.balanceOf(depositor), initialDepositorBalance - _assets, "Depositor balance should decrease by assets amount");

        // Verify that an equivalent amount of aTokens were minted
        assertApproxEqAbs(aToken.balanceOf(address(erc4626STAaveV3JTKernel)), _assets, 2, "An equivalent amount of aTokens should be minted");
    }
}
