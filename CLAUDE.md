# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The on-chain core of a USDC-style stablecoin, written in Solidity with Foundry and OpenZeppelin Contracts Upgradeable v5.
It was built step by step from `GUIDE.md` as a learning and portfolio project (originally Project 02 of the
`Mini-Blockchain` repo). The user is learning, so explain changes and reasoning instead of only producing code.

**Always run `forge test` after changing code, and show the output.** A change isn't done until its tests pass and `forge fmt --check` is clean.

## Commands (run from the repo root)

```bash
git submodule update --init --recursive        # after a fresh clone, if not cloned with --recursive
forge build
forge test -vv
forge test --match-test <name> -vvv            # single test
forge test --match-contract <Contract>
forge fmt                                      # CI runs: forge fmt --check, forge build --sizes, forge test -vvv
forge coverage --report summary
anvil                                          # local chain; deploy with forge script, interact with cast (see README)
```

Dependencies are git submodules in `lib/`: `forge-std` and `openzeppelin-contracts-upgradeable`. `remappings.txt` maps
`@openzeppelin/contracts-upgradeable/`, `@openzeppelin/contracts/` (the copy nested inside the upgradeable package), and `forge-std/`.

## Contract design to preserve (`src/StableCoin.sol`)

- UUPS upgradeable, deployed behind an `ERC1967Proxy`, set up by `initialize` (no constructor logic beyond `_disableInitializers()`). `_authorizeUpgrade` is restricted to `onlyRole(UPGRADER_ROLE)`, and every future version must keep that check.
- **6 decimals** (USDC-style): $1 = `1_000_000`.
- Roles: `DEFAULT_ADMIN_ROLE` (grants roles, sets minter allowances), `MINTER_ROLE` (mints up to its allowance, burns its own balance), `PAUSER_ROLE`, `BLOCKLISTER_ROLE`, `UPGRADER_ROLE`. Even the admin can't upgrade without `UPGRADER_ROLE`.
- Custom state lives in an **ERC-7201 namespaced storage struct** (`StableCoinStorage`). Append new fields only. Never reorder fields or add top-level state variables, because that corrupts storage across upgrades. Follow `UPGRADE_CHECKLIST.md` for any upgrade.
- Pause and blocklist checks go in the `_update` override, which every transfer, mint, and burn passes through. It checks `from`, `to`, **and `msg.sender`** (this blocks `transferFrom` by a blocklisted spender).
- Use custom errors (`ZeroAddress`, `AccountBlocklisted`, ...), not revert strings.

Testing pitfall: `vm.prank` applies to the *next external call*, and that includes a getter such as `coin.MINTER_ROLE()` inside `vm.expectRevert(...)`. Read role constants into local variables **before** calling `vm.prank`.

Keys: read deploy keys from environment variables or pass them on the command line. `.env` is gitignored, so never commit keys.

## Environment

The user's machine runs Windows with Git Bash. Shell commands in the docs are POSIX, so run them with the Bash tool.
