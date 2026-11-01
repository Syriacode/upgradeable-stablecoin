// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StableCoin} from "../src/StableCoin.sol";

/// @notice Deploys the StableCoin implementation and an ERC1967 proxy, initialized in the same transaction.
/// @dev The signing key is NOT read here. Pass it on the command line (--private-key / --account / --ledger),
///      so this script never handles secrets.
contract Deploy is Script {
    string internal constant NAME = "Test USD";
    string internal constant SYMBOL = "TUSD";

    function run() external returns (StableCoin implementation, StableCoin coin) {
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();

        implementation = new StableCoin();

        // Deploy + initialize atomically, so nobody can front-run initialize() and claim admin.
        bytes memory initData = abi.encodeCall(StableCoin.initialize, (NAME, SYMBOL, admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        coin = StableCoin(address(proxy));

        vm.stopBroadcast();

        console.log("Implementation:", address(implementation));
        console.log("Proxy (use this):", address(proxy));
        console.log("Admin:", admin);
    }
}
