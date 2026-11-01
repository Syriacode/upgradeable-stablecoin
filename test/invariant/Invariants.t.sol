// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../Base.t.sol";
import {Handler} from "./Handler.sol";

/// @notice Properties that must hold after ANY sequence of mints, transfers, and burns.
contract InvariantsTest is BaseTest {
    Handler internal handler;

    function setUp() public override {
        super.setUp();

        address[3] memory actors = [alice, bob, makeAddr("carol")];
        handler = new Handler(coin, minter, actors);

        // Only fuzz through the handler, never call the coin directly with unbounded inputs.
        targetContract(address(handler));
    }

    /// @dev If this breaks, money was created or destroyed out of thin air.
    function invariant_SupplyMatchesGhostAccounting() public view {
        assertEq(coin.totalSupply(), handler.ghostMinted() - handler.ghostBurned());
    }

    /// @dev Every token in the supply is owned by someone.
    function invariant_SupplyEqualsSumOfBalances() public view {
        assertEq(coin.totalSupply(), handler.sumBalances());
    }

    /// @dev Burning never refunds allowance, so supply can never pass the minter's original cap.
    function invariant_SupplyNeverExceedsInitialAllowance() public view {
        assertLe(coin.totalSupply(), MINTER_ALLOWANCE);
    }
}
