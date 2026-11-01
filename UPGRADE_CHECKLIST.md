# Upgrade Checklist — StableCoin

A UUPS upgrade replaces the logic behind every partner's balance in a single transaction. Treat it like a
production database migration that can't be undone: every box below is checked, by name, before execution.

## 1. Code review of the new implementation

- [ ] **Storage layout is compatible.**
  - `StableCoinStorage` fields are only **appended**: no reordering, retyping, renaming-with-new-meaning, or deletion.
  - The ERC-7201 namespace (`stablecoin.main`) and `STABLECOIN_STORAGE_LOCATION` constant are unchanged.
  - No new plain (non-namespaced) state variables. Put new state in the struct.
  - The inheritance list is unchanged, or every added parent uses namespaced storage (OpenZeppelin v5 `*Upgradeable` contracts do).
  - Run the OpenZeppelin upgrades validation (`openzeppelin-foundry-upgrades`, `Upgrades.validateUpgrade`) against the
    `@custom:oz-upgrades-from` reference. `forge inspect` doesn't show ERC-7201 namespaced fields, so a human also diffs the struct.
- [ ] **Upgrade authorization is still present.** `_authorizeUpgrade` keeps `onlyRole(UPGRADER_ROLE)`. A version that drops it
  lets anyone take over the proxy. A version that always reverts bricks all future upgrades.
- [ ] **Implementation is locked.** The constructor still calls `_disableInitializers()`.
- [ ] **No re-runnable setup.** `initialize` is not changed or exposed again. New setup logic goes in a
  `reinitializer(N)` function, called atomically through `upgradeToAndCall`.
- [ ] **Invariants still enforced.** Pause and blocklist checks remain in `_update`. Minter allowance accounting is untouched,
  unless that change is the point of the upgrade and has been reviewed as such.
- [ ] **Independent review or audit** of the full diff by someone who didn't write it. Findings are resolved or explicitly accepted.

## 2. Testing

- [ ] Full suite passes: `forge test`, including the fuzz and invariant tests, with 0 handler reverts.
- [ ] An upgrade test proves that balances, total supply, minter allowances, blocklist entries, roles, and pause state survive
  (`test/Upgrade.t.sol`).
- [ ] **Fork test against live state:** `forge test --fork-url $MAINNET_RPC`. Upgrade the real proxy in a fork, then re-check real
  holders' balances, real minter allowances, and real blocklist entries.
- [ ] The exact transaction (implementation address + calldata) is simulated (e.g. Tenderly or the multisig's simulator) and the
  resulting state diff is reviewed.

## 3. Deployment of the implementation

- [ ] Deploy the new implementation from a clean commit. Record the commit hash.
- [ ] Verify the source on the block explorer, and confirm the bytecode matches a local build.
- [ ] Confirm nobody can initialize the implementation directly (calling `initialize` on it reverts).

## 4. Governance and sign-off

- [ ] **Who signs:** the `UPGRADER_ROLE` holder is an M-of-N multisig (e.g. 3-of-5) whose signers are on separate devices and
  organizations. Signers independently verify the target proxy, the implementation address, and the calldata, not just the UI summary.
- [ ] **Timelock:** the upgrade is queued behind a timelock (e.g. 48–72h), so partners and monitoring can react before it executes.
- [ ] **Announcement:** partners and integrators get advance notice with the audit report, the timelock execution time, and
  expected behavior changes. Status page and support teams are briefed.
- [ ] Change-management ticket approved, linking the review, test results, and simulation.

## 5. Execution

- [ ] Execute `upgradeToAndCall(newImplementation, data)` through the timelock and multisig at the announced time.
- [ ] Decide in advance whether to `pause()` during the upgrade. If yes, the `PAUSER_ROLE` holder is on standby to unpause.

## 6. Post-upgrade verification

- [ ] The ERC-1967 implementation slot holds the new address, and an `Upgraded(newImplementation)` event was emitted.
- [ ] Smoke tests on mainnet: read a known holder's balance; do a small mint → transfer → burn with the issuance backend;
  confirm a blocklisted address is still blocked.
- [ ] Monitoring dashboards (supply vs. reserves, mint/burn events, role changes) show nothing unexpected for 24h.
- [ ] Partners are notified that the upgrade is complete.

## 7. Rollback plan (prepared before execution)

- [ ] **First response is `pause()`.** It freezes all balance changes while the team investigates.
- [ ] The previous implementation's address is recorded. Rolling back means upgrading to it again, which is only safe if the
  new version didn't write storage the old one misinterprets. This is confirmed during review, not during the incident.
- [ ] The rollback transaction is pre-built and simulated, and signers are on call.
- [ ] Incident communication templates for partners are ready.
