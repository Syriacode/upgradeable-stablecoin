// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title StableCoin
/// @notice A USDC-style stablecoin (6 decimals) deployed behind an ERC1967 proxy and upgraded via UUPS.
contract StableCoin is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BLOCKLISTER_ROLE = keccak256("BLOCKLISTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @custom:storage-location erc7201:stablecoin.main
    /// @dev Upgrade-safe layout: only ever APPEND new fields. Never reorder, retype, or delete existing ones.
    struct StableCoinStorage {
        mapping(address => uint256) minterAllowance;
        mapping(address => bool) blocklisted;
    }

    // cast index-erc7201 stablecoin.main
    // = keccak256(abi.encode(uint256(keccak256("stablecoin.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STABLECOIN_STORAGE_LOCATION =
        0x50ae98dd2400cbbc391405145f09a09ccf02c1c040857c852fae3fee3a3d6d00;

    error ZeroAddress();
    error ExceedsMinterAllowance(uint256 requested, uint256 remaining);
    error AccountBlocklisted(address account);

    event MinterAllowanceSet(address indexed minter, uint256 amount);
    event Blocklisted(address indexed account, bool status);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Lock the implementation so nobody can initialize (and take over) it directly.
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address admin) external initializer {
        if (admin == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __ERC20Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @dev One dollar = 1_000_000 units, matching USDC.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // --- minting & burning -------------------------------------------------

    /// @notice Set (overwrite, not add to) how much `minter` may still mint.
    function setMinterAllowance(address minter, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStableCoinStorage().minterAllowance[minter] = amount;
        emit MinterAllowanceSet(minter, amount);
    }

    function minterAllowance(address minter) external view returns (uint256) {
        return _getStableCoinStorage().minterAllowance[minter];
    }

    /// @notice Mint `amount` to `to`, spending the caller's minter allowance.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        StableCoinStorage storage $ = _getStableCoinStorage();
        uint256 remaining = $.minterAllowance[msg.sender];
        if (amount > remaining) revert ExceedsMinterAllowance(amount, remaining);

        // Effects before interactions: spend the allowance first, then mint.
        $.minterAllowance[msg.sender] = remaining - amount;
        _mint(to, amount);
    }

    /// @notice Burn `amount` from the caller's own balance (users send tokens to a minter to redeem).
    function burn(uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(msg.sender, amount);
    }

    // --- pause --------------------------------------------------------------

    /// @notice Emergency stop: freezes every transfer, mint, and burn.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // --- blocklist ----------------------------------------------------------

    function setBlocklisted(address account, bool status) external onlyRole(BLOCKLISTER_ROLE) {
        _getStableCoinStorage().blocklisted[account] = status;
        emit Blocklisted(account, status);
    }

    function isBlocklisted(address account) public view returns (bool) {
        return _getStableCoinStorage().blocklisted[account];
    }

    // --- internals ---------------------------------------------------------

    /// @dev Every balance change (transfer, transferFrom, mint, burn) flows through here, so the pause
    ///      and blocklist checks can't be bypassed by any entry point. Checking msg.sender as well as
    ///      from/to stops a blocklisted spender from moving someone else's tokens via transferFrom.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        if (isBlocklisted(from)) revert AccountBlocklisted(from);
        if (isBlocklisted(to)) revert AccountBlocklisted(to);
        if (isBlocklisted(_msgSender())) revert AccountBlocklisted(_msgSender());
        super._update(from, to, value); // ERC20Pausable: reverts with EnforcedPause while paused
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function _getStableCoinStorage() private pure returns (StableCoinStorage storage $) {
        assembly {
            $.slot := STABLECOIN_STORAGE_LOCATION
        }
    }
}
