# Project 02 — Build a Mintable Stablecoin (step-by-step guide)

**Goal:** build the core of a USDC-style stablecoin in Solidity, behind an upgradeable proxy, with minter
allowances, pause, a blocklist, and fuzz + invariant tests, then deploy it to a local chain.

**Why this project:** it maps line-by-line to the Coinbase *Senior Software Engineer, Stablecoins* role:

| Job requirement | Where you practice it |
|---|---|
| Smart contracts that *mint, burn, and safeguard supply* | Steps 3, 5 |
| *Access control* | Steps 3, 4 |
| *Upgradeability*, shipping changes *secure and auditable* | Steps 2, 6 |
| *Well-tested code* | Every step; Step 5 for fuzz/invariants |
| *Key management* | Steps 3, 7 |
| *Uses generative AI responsibly, with human oversight* | The "You check" box in every step + Step 8 write-up |

Everything runs on a **local test chain with play money**. No real crypto, wallet, or cost.

**Time:** about 6–10 hours across several sessions. One step per sitting is a good pace.

---

## How to use this guide with Claude Code

Every step has the same five parts:

- **Learn:** the concept, in a few sentences. Read it before prompting.
- **Prompt:** what to type into Claude Code. Use it as-is or rephrase it. Rephrasing in your own words helps you learn.
- **You check:** what *you* verify in the diff before accepting. This is the human-oversight part. Don't skip it.
- **Done when:** a command whose output proves the step works.
- **Commit:** the commit message to use.

Three habits that make Claude Code a teacher, not just a code generator:

1. **Plan first on bigger steps.** Press `Shift+Tab` to switch to plan mode, review the plan, then let it write.
2. **Ask "why" after every change.** For example: *"Explain line by line what you just changed and what would break if I removed each line."*
3. **Make it prove things.** For example: *"Run the tests and show me the output"* rather than trusting "this should work".

Each step ends with an **Interview question**. Answer it out loud or in a notes file. These are the questions a stablecoin team asks.

---

## Step 0 — Install the tools (15 min)

**Learn.** [Foundry](https://book.getfoundry.sh) is the Solidity toolkit used by most professional teams. It has four parts:
`forge` compiles and tests, `anvil` runs a local blockchain, `cast` talks to a chain from the terminal, and `chisel` is a Solidity REPL.
Tests are written in Solidity itself, so you only need one language.

**Do it yourself** (this is just setup):

```bash
curl -L https://foundry.paradigm.xyz | bash   # then open a new terminal
foundryup
forge --version                                # expect 1.x
```

Then open your repo in Claude Code:

```bash
cd Mini-Blockchain
claude
```

**Prompt:**
> Run /init to create a CLAUDE.md for this repo. Mention that 01-simple-chain is Python with pytest,
> and 02-stablecoin will be a Foundry/Solidity project. Add a rule: always run the relevant tests after changing code.

**You check:** read the generated `CLAUDE.md`. It's loaded into every future session, so make sure it's accurate.

**Commit:** `Add CLAUDE.md project instructions`

---

## Step 1 — Scaffold the Foundry project (15 min)

**Learn.** Foundry stores libraries as **git submodules** in `lib/`. This project lives *inside* your existing repo,
so you must stop `forge init` from creating a second git repo nested inside it.

**Prompt:**
> Inside 02-stablecoin (which already contains GUIDE.md), set up a Foundry project. Run exactly:
> `forge init --force --no-git .`, then `rm -rf lib/forge-std`,
> then `forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts-upgradeable`.
> Delete the sample Counter contract, test, and script. Create remappings.txt mapping
> `@openzeppelin/contracts-upgradeable/` to `lib/openzeppelin-contracts-upgradeable/contracts/`,
> `@openzeppelin/contracts/` to `lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/`,
> and `forge-std/` to `lib/forge-std/src/`. Add a .gitignore for cache/ and out/. Then run forge build.

> ⚠️ **Watch out:** if you ever see a `.git` folder inside `02-stablecoin/`, it created a nested repo. Delete it.
> Run `cat ../.gitmodules` from inside `02-stablecoin`: it should list both libraries under `02-stablecoin/lib/`.

**You check:** `../.gitmodules` lists `forge-std` and `openzeppelin-contracts-upgradeable`, and there's no nested `.git`.

**Done when:** `forge build` prints *Compiler run successful* (or *Nothing to compile*).

**Commit:** `Scaffold Foundry project for stablecoin`

**Interview question:** *Why do we use the `-upgradeable` variant of OpenZeppelin instead of the regular one?*

---

## Step 2 — An upgradeable token behind a proxy (1 hr)

**Learn.** A deployed contract's code can never change. To make a token "upgradeable", users talk to a small
**proxy** contract that holds all the *storage* (balances), and it forwards every call to an **implementation**
contract that holds the *logic*. Upgrading means pointing the proxy at a new implementation, while the balances stay put.

Consequences you must understand:
- **No constructors for setup.** The constructor runs in the implementation's context, not the proxy's. Use an `initialize()` function instead.
- **`initialize()` must run exactly once**, or an attacker could call it and make themselves admin. OpenZeppelin's `initializer` modifier enforces this.
- **Lock the implementation itself** by calling `_disableInitializers()` in its constructor.
- We use **UUPS** proxies: the upgrade function lives in the implementation and is protected by your own access check.

Also: USDC uses **6 decimals**, not 18. One dollar is `1_000_000` units.

**Prompt (use plan mode):**
> Create src/StableCoin.sol: a UUPS-upgradeable ERC-20 using OpenZeppelin upgradeable v5 —
> inherit Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable.
> Constructor only calls _disableInitializers(). initialize(name, symbol, admin) sets up ERC20 and AccessControl
> and grants DEFAULT_ADMIN_ROLE to admin; revert with a custom error ZeroAddress if admin is address(0).
> decimals() returns 6. Leave _authorizeUpgrade empty for now with a TODO — we lock it down in step 3.
> Then create test/Base.t.sol: an abstract test contract whose setUp deploys the implementation and an
> ERC1967Proxy with the initialize call encoded via abi.encodeCall, and casts the proxy to StableCoin.
> Use makeAddr for named test accounts (admin, alice, bob).
> Create test/StableCoin.t.sol with tests for: name/symbol/decimals, admin has the admin role,
> and that calling initialize a second time reverts with InvalidInitialization.

**You check:**
- The test talks to the **proxy** address, not the implementation. Ask: *"Which address does `coin` point to in the tests, and why does that matter?"*
- `_disableInitializers()` is in the constructor.
- The empty `_authorizeUpgrade` is a deliberate, temporary hole. Note it and close it in Step 3.

**Done when:** `forge test -vv` shows all tests passing.

**Commit:** `Add upgradeable StableCoin skeleton behind ERC1967 proxy`

**Interview question:** *What happens if you forget `_disableInitializers()` in the implementation's constructor?*

---

## Step 3 — Roles, minter allowances, mint and burn (1.5 hr)

**Learn.** Real stablecoins never have a single "owner" key that can do everything. Power is split into **roles**,
so a leaked key has limited blast radius:

| Role | Can do | Real-world holder |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | grant/revoke roles, set minter allowances | multisig, kept cold |
| `MINTER_ROLE` | mint up to its allowance, burn its own balance | issuance backend service |
| `PAUSER_ROLE` | pause/unpause (Step 4) | on-call security team |
| `BLOCKLISTER_ROLE` | blocklist addresses (Step 4) | compliance team |
| `UPGRADER_ROLE` | upgrade the implementation | multisig + timelock |

**Minter allowances** (USDC's model): each minter has a cap that *decreases* as it mints. A compromised minter
key can only mint up to its remaining allowance, not unlimited money. **Burning** works the way USDC does it:
a user sends tokens to a minter, and the minter burns from its own balance.

**Storage in upgradeable contracts:** new state variables can collide with storage slots in later versions.
OpenZeppelin v5 uses **ERC-7201 namespaced storage**: put your custom state in a struct at a computed slot.
Compute the slot with `cast index-erc7201 stablecoin.main`.

**Prompt (plan mode):**
> Add four role constants: MINTER_ROLE, PAUSER_ROLE, BLOCKLISTER_ROLE, UPGRADER_ROLE (keccak256 of their names).
> Store custom state using ERC-7201 namespaced storage: a struct StableCoinStorage with
> `mapping(address => uint256) minterAllowance`, at the slot from `cast index-erc7201 stablecoin.main`
> (run the command and paste the result into a constant; add the @custom:storage-location annotation).
> Add: setMinterAllowance(minter, amount) — admin only, emits MinterAllowanceSet;
> minterAllowance(minter) view; mint(to, amount) — MINTER_ROLE only, reverts with
> ExceedsMinterAllowance(requested, remaining) if over allowance, otherwise decreases the allowance then mints;
> burn(amount) — MINTER_ROLE only, burns from msg.sender.
> Make _authorizeUpgrade require UPGRADER_ROLE.
> In Base.t.sol, grant each role to its own named account and give the minter an allowance of 1,000,000 dollars (in 6-decimal units).
> Write tests: mint reduces allowance, mint over allowance reverts with the exact error and arguments,
> a non-minter cannot mint (expect AccessControlUnauthorizedAccount), burn reduces total supply,
> and a non-admin cannot set allowances.

> ⚠️ **Classic Foundry trap.** This test **fails**:
> ```solidity
> vm.prank(alice);
> vm.expectRevert(abi.encodeWithSelector(..., alice, coin.MINTER_ROLE()));
> coin.mint(alice, 1);
> ```
> `vm.prank` applies to the *next call*, and `coin.MINTER_ROLE()` is a call. So the prank gets used up there,
> and `mint` runs as the test contract. Fix it by reading the role into a local variable **before** `vm.prank`.
> If Claude writes it this way, ask it to explain the failure before fixing it. That's a great learning moment.

**You check:**
- `mint` updates the allowance **before** calling `_mint`. Ask Claude: *"Why does the order matter here?"*
- The storage slot constant actually equals the `cast` output. Run the command yourself.
- `_authorizeUpgrade` now has `onlyRole(UPGRADER_ROLE)`.

**Done when:** `forge test -vv` all pass.

**Commit:** `Add role-based access control and minter allowances`

**Interview question:** *A minter's key leaks. What's the maximum damage, and what are the first two transactions you'd send?*

---

## Step 4 — Pause and blocklist (1 hr)

**Learn.** Regulated stablecoins need two emergency controls. **Pause** freezes all transfers during an incident.
The **blocklist** stops specific addresses from sending or receiving tokens, for example because of sanctions or stolen funds.

In OpenZeppelin v5, every balance change (transfer, mint, and burn) flows through one internal function, `_update`.
Hook your checks there, and they apply everywhere without you having to remember each function.

**Prompt:**
> Add ERC20PausableUpgradeable (init it in initialize). Add pause()/unpause() restricted to PAUSER_ROLE.
> Add a `mapping(address => bool) blocklisted` to the ERC-7201 struct (append it; never reorder fields).
> Add setBlocklisted(account, status) — BLOCKLISTER_ROLE only, emits Blocklisted — and isBlocklisted view.
> Override _update so it reverts with AccountBlocklisted(account) if `from`, `to`, or msg.sender is blocklisted, then calls super.
> Tests: transfers revert while paused with EnforcedPause; unpause restores them; blocklisted sender can't send;
> blocklisted recipient can't receive; a blocklisted spender can't use transferFrom even with an approval;
> minting to a blocklisted address reverts.

**You check:**
- Why does `_update` check `msg.sender` too? Ask Claude to name an attack that works without that check (hint: `approve` + `transferFrom`).
- New struct fields go **at the end**. Ask: *"What breaks if I insert a field in the middle after deployment?"*

**Done when:** `forge test -vv` all pass.

**Commit:** `Add pause and blocklist enforced in _update`

**Interview question:** *Pause and blocklist are powerful. How do you stop them from being abused by your own team?*

---

## Step 5 — Fuzz and invariant tests (1.5 hr)

**Learn.** Unit tests check cases *you* thought of. **Fuzz tests** let Foundry generate hundreds of random inputs.
**Invariant tests** go further: Foundry calls random sequences of functions, and after every call it checks
properties that must **always** hold. For a stablecoin, the most important one is:

> **total supply == everything ever minted − everything ever burned**

If that ever breaks, money was created or destroyed out of thin air.

The standard pattern is a **Handler** contract that wraps your token's functions with valid, bounded inputs and
tracks expected totals in "ghost variables". The invariant test then points Foundry at the handler.

**Prompt (plan mode):**
> Add a fuzz test: mint a random amount (bounded 1 to the minter's allowance) then burn it, and assert supply returns to 0.
> Then create test/invariant/Handler.sol: it holds the coin, the minter, and three actor addresses, and exposes
> mint(actorIndex, amount), transfer(fromIndex, toIndex, amount), and burn(actorIndex, amount) where burn transfers
> to the minter and the minter burns. Bound all amounts so calls don't revert. Track ghostMinted and ghostBurned,
> and provide sumBalances(). Create test/invariant/Invariants.t.sol extending Base, deploy the Handler,
> targetContract(handler), and assert: totalSupply == ghostMinted - ghostBurned; totalSupply == sumBalances();
> totalSupply <= the initial minter allowance. Add an [invariant] section to foundry.toml with runs = 64, depth = 64.

**You check:**
- Break the contract on purpose: in `mint`, mint `amount + 1`. Run the tests and watch the invariant catch it. Then revert the change.
  *This is the single best way to trust a test suite.*
- Read the "calls" and "reverts" counts in the output. If nearly every call reverts, the handler isn't testing anything.

**Done when:** `forge test` passes and the invariant output shows thousands of calls with 0 reverts.

**Commit:** `Add fuzz and invariant tests for supply accounting`

**Interview question:** *What invariants would you add if the token also paid rewards to holders?*

---

## Step 6 — Ship an upgrade safely (1 hr)

**Learn.** Upgrades are where real money gets lost. The common failures are: storage layout changes that scramble
balances, a new version that forgets the upgrade-authorization check (bricking future upgrades), and an
initializer that can be re-run. You'll practice a safe upgrade and write the checklist a team would use.

**Prompt:**
> Create src/StableCoinV2.sol that inherits StableCoin and adds only `function version() external pure returns (string memory) { return "2"; }`.
> Tests: (1) mint to alice, upgrade the proxy to V2 as the upgrader using upgradeToAndCall, assert version() == "2"
> and that alice's balance, the minter allowance, a blocklist entry, and role assignments all survived;
> (2) a non-upgrader (even the admin) cannot upgrade.
> Then write UPGRADE_CHECKLIST.md with the steps a team should follow before upgrading a live stablecoin.

**You check:**
- Ask Claude: *"Write a bad V2 that adds a state variable at the top of StableCoin instead of using the namespaced struct. Would it corrupt balances? Show me with a test."* Then delete the bad version.
- Review the checklist critically. Add anything missing, like who signs, the timelock, testing on a fork, a rollback plan, and an announcement to partners.

**Done when:** upgrade tests pass and `UPGRADE_CHECKLIST.md` is something you'd defend in an interview.

**Commit:** `Add V2 upgrade test and upgrade checklist`

**Interview question:** *Walk me through how you'd upgrade the contract that holds $1B of partner stablecoins.*

---

## Step 7 — Deploy to a local chain and talk to it (45 min)

**Learn.** `anvil` starts a local Ethereum node with 10 pre-funded **test accounts**. Their private keys are
public and printed on startup, which is fine locally and never OK on a real network. `forge script` deploys,
and `cast` calls functions from your terminal, the same way an ops engineer pokes at production.

**Key management note:** in real deployments, keys live in hardware wallets, multisigs, or cloud KMS, and are
never pasted into terminals or committed. Even locally, read keys from an environment variable, and keep `.env` in `.gitignore`.

**Prompt:**
> Write script/Deploy.s.sol that reads ADMIN from the environment, deploys the implementation and an ERC1967Proxy
> with initialize, and logs both addresses. Then give me the exact commands to: start anvil in a second terminal;
> deploy using anvil's first test account; grant MINTER_ROLE and set an allowance with cast send; mint 250 dollars
> to anvil's second account; and read its balance with cast call. Explain each command before I run it.

**You check:** run the commands **yourself** in a terminal, one by one, and predict each output before you hit enter.
You should end with a balance of `250000000`, which is 250 dollars at 6 decimals.

**Done when:** you minted and read a balance on your local chain.

**Commit:** `Add deploy script`

**Interview question:** *Your deploy script is about to run on mainnet. What could go wrong between deploying the implementation and initializing the proxy?*

---

## Step 8 — Polish it for GitHub and interviews (1 hr)

**Prompt 1: CI.**
> Add a GitHub Actions workflow at the repo root (.github/workflows/stablecoin.yml) that runs on push and PR,
> checks out with submodules recursive, installs Foundry with foundry-rs/foundry-toolchain@v1, and in
> 02-stablecoin runs forge fmt --check, forge build --sizes, and forge test -vvv. Also run forge fmt now.

**Prompt 2: security pass.**
> Run forge coverage --report summary and tell me which lines and branches aren't covered. Add tests for the important ones.
> Then review StableCoin.sol as a skeptical auditor: list issues by severity, with anything you'd want changed before mainnet.

Optionally install [Slither](https://github.com/crytic/slither) (`pip install slither-analyzer`) and run `slither .` in `02-stablecoin`.
For every finding, decide whether it's real or a false positive, and write down why.

**Prompt 3: README.**
> Write 02-stablecoin/README.md: what it is, the role table, how to run tests and deploy locally,
> design decisions (why UUPS, why minter allowances, why ERC-7201, why checks in _update),
> known limitations, and a final section "How I used Claude Code" — leave that section as headings for me to fill in.

**Write the "How I used Claude Code" section yourself.** Cover: what you delegated, what you reviewed, a bug
you caught (the `vm.prank` trap is a great example), and something you changed by hand. This is direct evidence
for the job requirement *"utilizes generative AI responsibly, maintaining human oversight."*

**Done when:** CI is green on GitHub, and the README reads well to someone who's never seen the project.

**Commit:** `Add CI, coverage tests, and project README`

---

## When you're done

You'll have a tested, upgradeable, role-separated stablecoin, which is the on-chain half of Coinbase Custom Stablecoins.
Next in the Coinbase-prep track:

- **Project B:** a Go service that watches your contract's Mint/Burn events and reconciles them against a reserve ledger.
- **Project C:** a factory that deploys one stablecoin per partner brand, plus a Go onboarding API (the capstone).
