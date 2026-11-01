// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title StableCoin
/// @notice A USDC-style stablecoin (6 decimals) deployed behind an ERC1967 proxy and upgraded via UUPS.
contract StableCoin is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    error ZeroAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Lock the implementation so nobody can initialize (and take over) it directly.
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address admin) external initializer {
        if (admin == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @dev One dollar = 1_000_000 units, matching USDC.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // TODO(step 3): restrict to UPGRADER_ROLE. Right now ANYONE can upgrade the proxy.
    function _authorizeUpgrade(address newImplementation) internal override {}
}
