// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StableCoin} from "../src/StableCoin.sol";

/// @notice Shared setup: deploys StableCoin behind an ERC1967 proxy, the way it runs in production.
abstract contract BaseTest is Test {
    string internal constant NAME = "Test USD";
    string internal constant SYMBOL = "TUSD";

    StableCoin internal implementation;
    StableCoin internal coin; // the proxy, typed as StableCoin; always test through this

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public virtual {
        implementation = new StableCoin();

        bytes memory initData = abi.encodeCall(StableCoin.initialize, (NAME, SYMBOL, admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        coin = StableCoin(address(proxy));
    }
}
