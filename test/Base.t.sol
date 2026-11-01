// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StableCoin} from "../src/StableCoin.sol";

/// @notice Shared setup: deploys StableCoin behind an ERC1967 proxy, the way it runs in production.
abstract contract BaseTest is Test {
    string internal constant NAME = "Test USD";
    string internal constant SYMBOL = "TUSD";

    uint256 internal constant ONE_DOLLAR = 1e6; // 6 decimals
    uint256 internal constant MINTER_ALLOWANCE = 1_000_000 * ONE_DOLLAR;

    StableCoin internal implementation;
    StableCoin internal coin; // the proxy, typed as StableCoin; always test through this

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal pauser = makeAddr("pauser");
    address internal blocklister = makeAddr("blocklister");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public virtual {
        implementation = new StableCoin();

        bytes memory initData = abi.encodeCall(StableCoin.initialize, (NAME, SYMBOL, admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        coin = StableCoin(address(proxy));

        // Read role ids before startPrank so the getter calls don't run as admin.
        bytes32 minterRole = coin.MINTER_ROLE();
        bytes32 pauserRole = coin.PAUSER_ROLE();
        bytes32 blocklisterRole = coin.BLOCKLISTER_ROLE();
        bytes32 upgraderRole = coin.UPGRADER_ROLE();

        vm.startPrank(admin);
        coin.grantRole(minterRole, minter);
        coin.grantRole(pauserRole, pauser);
        coin.grantRole(blocklisterRole, blocklister);
        coin.grantRole(upgraderRole, upgrader);
        coin.setMinterAllowance(minter, MINTER_ALLOWANCE);
        vm.stopPrank();
    }
}
