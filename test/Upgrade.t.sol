// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {StableCoinV2} from "../src/StableCoinV2.sol";
import {BaseTest} from "./Base.t.sol";

contract UpgradeTest is BaseTest {
    function test_UpgradePreservesState() public {
        uint256 minted = 250 * ONE_DOLLAR;

        // --- state before the upgrade ---
        vm.prank(minter);
        coin.mint(alice, minted);

        vm.prank(blocklister);
        coin.setBlocklisted(bob, true);

        // --- upgrade ---
        StableCoinV2 v2 = new StableCoinV2();
        vm.prank(upgrader);
        coin.upgradeToAndCall(address(v2), "");

        StableCoinV2 coinV2 = StableCoinV2(address(coin)); // same proxy address, new logic
        assertEq(coinV2.version(), "2");

        // --- balances and supply survived ---
        assertEq(coinV2.balanceOf(alice), minted);
        assertEq(coinV2.totalSupply(), minted);

        // --- custom ERC-7201 state survived ---
        assertEq(coinV2.minterAllowance(minter), MINTER_ALLOWANCE - minted);
        assertTrue(coinV2.isBlocklisted(bob));
        assertFalse(coinV2.isBlocklisted(alice));

        // --- role assignments survived ---
        assertTrue(coinV2.hasRole(coinV2.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(coinV2.hasRole(coinV2.MINTER_ROLE(), minter));
        assertTrue(coinV2.hasRole(coinV2.PAUSER_ROLE(), pauser));
        assertTrue(coinV2.hasRole(coinV2.BLOCKLISTER_ROLE(), blocklister));
        assertTrue(coinV2.hasRole(coinV2.UPGRADER_ROLE(), upgrader));
    }

    function test_RevertWhen_NonUpgraderUpgrades() public {
        StableCoinV2 v2 = new StableCoinV2();
        bytes32 upgraderRole = coin.UPGRADER_ROLE(); // read before vm.prank

        // Even the admin can't upgrade directly. It would first have to grant itself
        // UPGRADER_ROLE, which emits a RoleGranted event that monitoring can catch.
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, upgraderRole)
        );
        vm.prank(admin);
        coin.upgradeToAndCall(address(v2), "");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, upgraderRole)
        );
        vm.prank(alice);
        coin.upgradeToAndCall(address(v2), "");
    }
}
