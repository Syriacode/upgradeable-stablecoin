// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StableCoin} from "./StableCoin.sol";

/// @title StableCoinV2
/// @notice Practice upgrade: identical to V1 plus version(). Inheriting StableCoin keeps the storage layout,
///         the _disableInitializers() constructor, and the UPGRADER_ROLE check on _authorizeUpgrade.
/// @custom:oz-upgrades-from StableCoin
contract StableCoinV2 is StableCoin {
    function version() external pure returns (string memory) {
        return "2";
    }
}
