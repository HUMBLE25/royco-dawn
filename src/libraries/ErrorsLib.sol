// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library ErrorsLib {
    error MARKET_EXISTS();
    error NONEXISTANT_MARKET();
    error EXPECTED_LOSS_EXCEEDS_MAX();
    error POSITION_IS_HEALTHY();
    error POSITION_IS_UNHEALTHY();
    error CANNOT_REDEEM_MORE_THAN_OWNED();
}
