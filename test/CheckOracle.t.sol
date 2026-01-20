// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

interface IAggregatorV3 {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
}

contract CheckOracle is Test {
    function test_checkOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 24_273_135);

        address oracle = 0x04D840b7495b1e2EE4855B63B50F96c298651e99;
        IAggregatorV3 agg = IAggregatorV3(oracle);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = agg.latestRoundData();

        console.log("Oracle Address:", oracle);
        console.log("Decimals:", agg.decimals());
        console.log("Description:", agg.description());
        console.log("Round ID:", roundId);
        console.log("Answer:", uint256(answer));
        console.log("Started At:", startedAt);
        console.log("Updated At:", updatedAt);
        console.log("Answered In Round:", answeredInRound);
        console.log("Current Block Timestamp:", block.timestamp);
        console.log("Time diff (seconds):", block.timestamp - updatedAt);
    }
}
