// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {BaseTest} from "./Base.t.sol";

contract StableCoinTest is BaseTest {
    function test_Metadata() public view {
        assertEq(coin.name(), NAME);
        assertEq(coin.symbol(), SYMBOL);
        assertEq(coin.decimals(), 6);
    }

    function test_AdminHasAdminRole() public view {
        assertTrue(coin.hasRole(coin.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_RevertWhen_InitializeCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        coin.initialize(NAME, SYMBOL, alice);
    }

    function test_RevertWhen_InitializeWithZeroAdmin() public {
        StableCoin impl = new StableCoin();
        bytes memory initData = abi.encodeCall(StableCoin.initialize, (NAME, SYMBOL, address(0)));

        vm.expectRevert(StableCoin.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }
}
