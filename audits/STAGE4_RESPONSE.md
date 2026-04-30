# AiPunks — Stage 4 Audit Response

**Job:** LeftClaw Build Job #83 ("Ai Punks")
**Contract:** `packages/foundry/contracts/AiPunks.sol`
**Tests:** `packages/foundry/test/AiPunks.t.sol` (21 tests, all passing)
**Auditor responder:** clawdbotatg (Stage 4)
**Date:** 2026-04-30

This document is a one-line-per-finding response to every item in
`STAGE3_AUDIT.md`. Status keys: **FIXED**, **DOCUMENTED** (the audit
recommended documentation, not a code change), **WON'T FIX** (intentional
trade-off).

---

## Mediums

### M-1 — `withdraw()` is push-payment to `owner()`
**Status:** FIXED (documented).
**Where:** `AiPunks.sol:withdraw()` — NatSpec now explains the failure mode
and the recovery path (`transferOwnership` to a payable wallet). The
`call`-based push pattern is retained — `WithdrawFailed()` is already a
custom error and funds are not permanently locked. Test:
`test_withdraw_revertsForNonPayableOwner` etches a non-payable contract as
owner, asserts `WithdrawFailed`, transfers ownership back, and confirms the
ETH is recoverable.

### M-2 — Per-wallet free-mint cap is Sybil-able via wallet cycling
**Status:** FIXED (mitigated, not eliminated).
**Where:** new `MAX_FREE_MINTS = 2_000` constant (20% of supply), new
`totalFreeMintsUsed` state var, `mint()` clamps `freeUsed` against
`MAX_FREE_MINTS - totalFreeMintsUsed`. Bounds the worst case: a single
holder cycling wallets can claim at most 2,000 free mints, leaving 8,000
paid mints worth of revenue to the collection. Loud disclosure added in the
contract NatSpec (lines 40-47). Public view `freeMintsRemainingGlobal()`
exposed for the dApp. Test: `test_globalFreeMintCap` walks 100 wallets to
exhaust the cap and confirms the 101st must pay full price even with CLAWD.

### M-3 — `setClawdUsdPrice` has no bounds
**Status:** FIXED.
**Where:** `setClawdUsdPrice()` now checks `newPrice <= MAX_CLAWD_USD_PRICE`
(`1e18` = $1.00 per whole CLAWD). Reverts `PriceTooHigh()` above that. Test:
`test_setClawdUsdPrice_onlyOwner_andBound` asserts boundary at `1e18` and
revert at `1e18 + 1`. Time-lock and event-rate-limiting deliberately not
added (out of 1.5h scope; documented as a known centralization surface).

---

## Lows

### L-1 — Unbounded `clawdBal * clawdUsdPrice` overflow
**Status:** FIXED (transitively).
**Where:** the M-3 bound (`MAX_CLAWD_USD_PRICE = 1e18`) keeps
`clawdBal * price` below `~1e47` in any plausible CLAWD distribution
(CLAWD total supply is ~1e29). `Math.mulDiv` was considered as
belt-and-suspenders but skipped — the bound is sufficient, and avoiding the
extra import keeps the diff minimal. Documented in the `freeMintsEligible`
NatSpec.

### L-2 — `mint(quantity)` has no per-call upper bound
**Status:** FIXED.
**Where:** new `MAX_BATCH = 50` constant + `BatchTooLarge()` error in
`mint()`. Test: `test_batchTooLargeReverts` asserts revert at 51 and pass
at 50.

### L-3 — Refund failure reverts the whole mint
**Status:** DOCUMENTED.
**Where:** comment added in `mint()` near the refund block explaining the
contract-receiver footgun: contract callers whose `receive()` reverts must
send `msg.value` exactly equal to `required`. Behavior unchanged — the
status quo is acceptable per the audit, and shipping `pendingWithdrawals`
would be more code than it's worth for a known footgun that EOAs cannot
trigger.

### L-4 — `setRoyalty` can set up to 100% royalty + missing event
**Status:** FIXED.
**Where:** new `MAX_ROYALTY_BPS = 1_000` (10%) cap, `RoyaltyTooHigh()` +
`ZeroAddress()` errors, new `RoyaltyUpdated` event emitted on every change.
Test: `test_setRoyalty_capAndZeroAddress` covers all three branches.

---

## Infos

### I-1 — Owner can change `mintPrice` arbitrarily, including to zero
**Status:** WON'T FIX (documented as standard centralization).
**Where:** standard Ownable pattern — the owner is the client and is
trusted by design. README will note the centralization surfaces.

### I-2 — Owner can withdraw all proceeds at any time
**Status:** WON'T FIX (by design).
**Where:** matches the spec ("owner withdraws mint proceeds"). Documented.

### I-3 — `_safeMint` triggers `onERC721Received` reentrancy surface
**Status:** WON'T FIX (no exploit).
**Where:** `nonReentrant` already in place; state fully updated before the
mint loop. Audit confirms no invariant break.

### I-4 — Free-mint counts truncate cents (intentional)
**Status:** DOCUMENTED.
**Where:** `freeMintsEligible` NatSpec now spells out the truncation
behavior explicitly ("$999.99 → 0, $1,000.00 → 1, …").

### I-5 — `clawdUsdPrice = 0` default disables free mints
**Status:** DOCUMENTED.
**Where:** already in the contract NatSpec (lines 23-26). The dApp will
surface "free mints currently disabled" when the price is zero — to be
implemented in Stage 6.

### I-6 — No off-chain "free mints used" event for indexers
**Status:** WON'T FIX (cosmetic).
**Where:** the existing `Minted(buyer, quantity, freeUsed, paid)` event
already carries `freeUsed` per-mint, which is sufficient for indexers to
reconstruct per-wallet totals. Adding a second redundant event is not worth
the extra log gas.

---

## Build & test status

- `cd packages/foundry && forge build` — **exit 0**, only pre-existing
  scaffold lint notes (camel-case style, vm cheatcode notes in
  `script/VerifyAll.s.sol`); no errors, no contract warnings.
- `cd packages/foundry && forge test --match-contract AiPunksTest` —
  **21 / 21 passed**, 0 failed, 0 skipped.
- `yarn compile` (repo root) — **exit 0**.

## GitHub issues closed

- `#1` (M-1) — fixed in this commit.
- `#2` (M-2) — fixed in this commit.
- `#3` (M-3) — fixed in this commit.

---

*End of Stage 4 response.*
