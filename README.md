# 02 — Mintable Stablecoin

The on-chain core of a USDC-style stablecoin, written in Solidity with Foundry and OpenZeppelin v5:

- an **ERC-20 with 6 decimals** ($1 = `1_000_000` units),
- deployed behind an **upgradeable UUPS proxy**,
- with **separated roles**, **capped minter allowances**, an **emergency pause**, and a **compliance blocklist**,
- covered by unit, fuzz, invariant, and upgrade tests, plus a CI pipeline.

Everything runs on a local test chain with play money. This was built step by step from [GUIDE.md](GUIDE.md).

## Roles

No single key can do everything. A leaked key has a limited blast radius.

| Role | Can do | Real-world holder |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | grant/revoke roles, set minter allowances | multisig, kept cold |
| `MINTER_ROLE` | mint up to its allowance, burn its own balance | issuance backend service |
| `PAUSER_ROLE` | pause/unpause all balance changes | on-call security team |
| `BLOCKLISTER_ROLE` | add/remove addresses from the blocklist | compliance team |
| `UPGRADER_ROLE` | upgrade the implementation | multisig + timelock |

## Layout

```
src/StableCoin.sol           the token (implementation behind the proxy)
src/StableCoinV2.sol         practice upgrade target: V1 + version()
test/Base.t.sol              shared setup: deploys via ERC1967Proxy, assigns every role
test/StableCoin.t.sol        unit + fuzz tests
test/Upgrade.t.sol           upgrade preserves state; only UPGRADER_ROLE may upgrade
test/invariant/              Handler + invariant tests for supply accounting
script/Deploy.s.sol          deploys implementation + initialized proxy
UPGRADE_CHECKLIST.md         what a team checks before upgrading a live token
```

## Run the tests

From this directory, after cloning with submodules (`git clone --recursive`, or `git submodule update --init --recursive`):

```bash
forge build
forge test -vv                                # all tests
forge test --match-test test_MintReducesAllowance -vvv  # a single test
forge test --match-path test/invariant/Invariants.t.sol # just the invariants
forge coverage --report summary
forge fmt --check
```

The invariant suite runs 64 random sequences of 64 calls (`[invariant]` in `foundry.toml`) and checks that:

- `totalSupply == minted − burned`,
- `totalSupply == sum of all balances`,
- `totalSupply <= the minter's original allowance`.

CI (`.github/workflows/stablecoin.yml` at the repo root) runs format check, build with contract sizes, and tests on every push and PR.

## Deploy locally

Start a local chain in a second terminal:

```bash
anvil
```

Then, in this directory (Git Bash syntax; these are anvil's public test accounts, never use them on a real network):

```bash
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil account #0
export ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266                                 # anvil account #0
export ALICE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8                                 # anvil account #1

# 1. Deploy implementation + proxy (initialize runs in the same transaction)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
export PROXY=<"Proxy (use this)" address from the output>

# 2. Make the admin a minter and give it a $1,000 allowance
cast send $PROXY "grantRole(bytes32,address)" $(cast keccak "MINTER_ROLE") $ADMIN --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $PROXY "setMinterAllowance(address,uint256)" $ADMIN 1000000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 3. Mint $250 to Alice, then read her balance
cast send $PROXY "mint(address,uint256)" $ALICE 250000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast call $PROXY "balanceOf(address)(uint256)" $ALICE --rpc-url $RPC_URL   # 250000000 [2.5e8]
```

The deploy script never reads a private key itself. The key is supplied on the command line, so the same script works
with `--ledger` or `--account` (an encrypted keystore) on a real network.

## Design decisions

### Why UUPS

A deployed contract's code can't change. A stablecoin, though, needs to fix bugs and meet new compliance requirements
without asking every holder to migrate. Users interact with an `ERC1967Proxy` that holds all storage and `delegatecall`s an
implementation contract for the logic. Upgrading points the proxy at a new implementation, and balances stay put.

UUPS (vs. the Transparent proxy pattern) puts the upgrade function in the implementation, guarded by our own check,
`_authorizeUpgrade` → `onlyRole(UPGRADER_ROLE)`. This gives a cheaper proxy with no admin-slot check on every call, and the
authorization uses the same role system as everything else. The cost is that every future version **must** keep that
check. A version without it can be taken over or bricked. That's why it's on the upgrade checklist and tested in
`test/Upgrade.t.sol`.

Related safeguards:
- The implementation's constructor calls `_disableInitializers()`, so nobody can initialize the bare implementation.
- `initialize` is guarded by `initializer`, so it runs exactly once.
- The deploy script encodes `initialize` into the proxy's constructor, so nobody can front-run it.

### Why minter allowances

This follows USDC's model. Each minter has a cap that **decreases** as it mints and is only refilled by the admin. If the
issuance backend's key leaks, the damage is bounded by its remaining allowance, not unlimited money. Minting checks and
spends the allowance **before** calling `_mint` (checks-effects-interactions). Burning doesn't refund the allowance, so
supply can never exceed what the admin has authorized in total. That property is an invariant test.

Burning follows the redemption flow: a holder sends tokens to a minter, and the minter burns from its own balance.
Users can't burn arbitrarily, so supply changes always go through an accountable party.

### Why ERC-7201 namespaced storage

In a proxy, storage layout is the contract with the past. If V2 shifts a variable into a slot V1 used for something
else, balances or permissions silently get reinterpreted. OpenZeppelin v5 keeps each module's state in a struct at a
slot derived from a namespace hash (ERC-7201), and this contract does the same:
`StableCoinStorage` lives at `cast index-erc7201 stablecoin.main`. Modules can't collide. The only rule left is: **append
new fields to the struct, never reorder, retype, or remove them.**

### Why the pause and blocklist checks live in `_update`

In OpenZeppelin v5, every balance change (`transfer`, `transferFrom`, `mint`, `burn`) goes through the internal
`_update` function. Putting the checks there means no entry point can bypass them, including ones added in future
versions. The override reverts if `from`, `to`, **or `msg.sender`** is blocklisted. Without the `msg.sender` check, a
blocklisted address that had been given an approval could still move a clean holder's tokens with `transferFrom`.
That attack has its own test. Pausing is inherited from `ERC20PausableUpgradeable`, which applies the same hook.

## Known limitations

This is a learning project, not a production token. Before mainnet I'd want to change or add:

- **Admin is a plain role.** `DEFAULT_ADMIN_ROLE` can grant itself any role, including `UPGRADER_ROLE`, and can be
  renounced or transferred in one step. `AccessControlDefaultAdminRulesUpgradeable` would add a two-step, delayed handover.
  In production, every role here would be held by a multisig or service key, with upgrades behind a timelock. None of
  that infrastructure is in this repo.
- **`setMinterAllowance` overwrites.** If the admin changes an allowance while the minter is minting, the minter can
  spend the old allowance and then receive the new one, the same race as ERC-20 `approve`. Increase/decrease functions
  or monitoring would address it.
- **Allowances aren't tied to the role.** Revoking `MINTER_ROLE` leaves the allowance in storage, and setting an allowance
  doesn't check that the address is a minter. Both are harmless today but untidy.
- **Blocklisted funds are frozen, not recoverable.** There's no wipe/seize function. Whether to add one is a policy decision.
- **Pause stops everything,** including burns and redemptions. A blocklisted minter also can't burn its own balance.
- **No gasless-transfer features.** There's no EIP-2612 `permit` or EIP-3009 `transferWithAuthorization`, which USDC supports.
- **No zero-address checks** on `setMinterAllowance` / `setBlocklisted`.
- **Upgrade safety is manual.** CI doesn't run OpenZeppelin's upgrade validation (`openzeppelin-foundry-upgrades`). Storage
  compatibility is checked by tests and the checklist.
- **Reserves are off-chain.** Nothing on-chain ties supply to dollars in a bank. That's the job of attestation and of
  the reconciliation service planned as the next project.
- `forge lint` reports two `reentrancy-events` warnings on the `MinterAllowanceSet` and `Blocklisted` emits. Neither
  function makes an external call, so they're treated as false positives.

## How I used Claude Code

### What I delegated

### What I reviewed

### A bug I caught

### Something I changed by hand

### What I'd do differently
