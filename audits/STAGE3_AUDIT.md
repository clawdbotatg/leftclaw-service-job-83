# AiPunks — Stage 3 Contract Audit Report

**Job:** LeftClaw Build Job #83 ("Ai Punks")
**Contract:** `packages/foundry/contracts/AiPunks.sol`
**Solidity:** `^0.8.20`
**Dependencies:** OpenZeppelin Contracts v5.6.1 (`ERC721`, `ERC2981`, `Ownable`, `ReentrancyGuard`, `Strings`, `IERC20`)
**Network:** Base mainnet
**Auditor:** clawdbotatg (Stage 3, read-only)
**Audit date:** 2026-04-30

This audit follows the EVM-audit-master methodology
(<https://raw.githubusercontent.com/austintgriffith/evm-audit-skills/main/evm-audit-master/SKILL.md>).
Skills loaded for this single-file collection: `evm-audit-general`,
`evm-audit-precision-math`, `evm-audit-erc20`, `evm-audit-erc721`,
`evm-audit-access-control`, `evm-audit-dos`, `evm-audit-oracles`.
Because the contract is small and self-contained, the parallel-agent
workflow was collapsed into a single, exhaustive walk by the orchestrator.

---

## Severity legend

- **Critical** — direct loss of funds, no preconditions.
- **High** — loss of funds with specific conditions, or permanent DoS.
- **Medium** — degraded behavior, trust-model violation, owner-only fund loss, or material spec deviation.
- **Low** — best-practice / latent issue without direct fund risk.
- **Info** — informational, no security impact.

## Summary table

| Severity | Count |
|---|---|
| Critical | 0 |
| High     | 0 |
| Medium   | 3 |
| Low      | 4 |
| Info     | 6 |
| **Total**| **13** |

## Final verdict

**READY for Stage 4 fixes.**

No Critical or High findings. The contract is functionally correct against
the on-chain spec for job #83 (10,000 supply, 0.069 ETH paid mint, ERC2981
5% royalty, $1,000 = 1 free mint capped at 20). Three Medium findings
(M-1 push-payment in `withdraw()`, M-2 wallet-cycling Sybil bypass of the
free-mint cap, M-3 owner-controlled USD oracle has no bounds / price-change
front-run) are concrete and fixable in Stage 4. The Lows and Infos are
hardening / disclosure items.

If Stage 4 elects "won't fix" on M-2 (wallet cycling), it must be disclosed
loudly in the README and the dApp UI; the cap is otherwise meaningless.

---

# Findings

## [M-1] `withdraw()` is push-payment to `owner()` — locked funds if owner is a non-payable contract
**Severity:** Medium
**Category:** access-control / general
**Location:** `AiPunks.sol:218-222` (`withdraw()`)

```solidity
function withdraw() external onlyOwner nonReentrant {
    uint256 bal = address(this).balance;
    (bool ok,) = payable(owner()).call{ value: bal }("");
    if (!ok) revert WithdrawFailed();
}
```

**Description:** `withdraw()` pushes the entire ETH balance to whatever
address currently owns the contract. If `owner()` is ever transferred to a
contract that lacks a payable `receive()` / `fallback()` (e.g. a Gnosis Safe
with no module that handles plain ETH transfers, or a contract that reverts
on receive), every subsequent `withdraw()` reverts with `WithdrawFailed()`
and ETH is permanently stuck until ownership is transferred again.

The job-83 client (`0x68B8...4599`) is an EOA today, so this is not exploitable
right now — but the contract is meant to live for years and ownership can be
transferred via OZ `Ownable.transferOwnership`.

**Impact:** Recoverable trapped funds requiring an ownership transfer dance;
classic push-vs-pull anti-pattern. Standard Medium per Sigma-Prime / Dacian.

**Recommendation:** Either (a) accept an explicit `recipient` argument
(`function withdraw(address payable to)` `onlyOwner`), or (b) implement a
pull pattern: store `pendingWithdrawals` and let any address claim its own
share. Option (a) is simplest and sufficient for a single-owner collection.

---

## [M-2] Free-mint cap is per-wallet, not per-holder — trivially bypassable by wallet cycling
**Severity:** Medium
**Category:** general / spec-compliance
**Location:** `AiPunks.sol:124-157` (`mint`), `AiPunks.sol:168-178` (`freeMintsEligible`)

**Description:** The free-mint cap is enforced on `usedFreeMints[msg.sender]`,
and eligibility is computed live from `CLAWD.balanceOf(msg.sender)`. After a
wallet has minted its 20 free mints, the holder can transfer the same CLAWD
position to a fresh wallet and mint another 20 free, repeat indefinitely. A
single $20,000 holder can free-mint the entire 10,000 supply for a few cents
of L2 gas per cycle.

The on-chain spec ("Cap 20 free mints per wallet") is technically satisfied
by the per-wallet mapping, but the *intent* — limiting free mints by USD
value held — is broken because USD value is a fungible bearer balance.

**Proof of concept:**
1. Holder H has 20,000 CLAWD-USD.
2. H calls `mint(20)` from wallet A → 20 free mints, `usedFreeMints[A]=20`.
3. H sends all CLAWD to wallet B.
4. H calls `mint(20)` from wallet B → 20 free mints, `usedFreeMints[B]=20`.
5. Repeat with wallets C, D, ... until 10,000 supply exhausted.
Cost: 500 wallet rotations × ~120k gas ≈ 60M gas total (~$0.50 on Base).

**Impact:** The whole collection can be claimed for free by a single
sufficiently-funded holder; paid mint revenue collapses to ~zero. This is a
material economic deviation from the spec's intent.

**Recommendation:** Pick one of these mitigations and document it:

- **(a)** Snapshot CLAWD balances at deploy / a fixed block, store the
  snapshot Merkle root, gate free mints by Merkle proof (cheapest to write,
  one-time off-chain work);
- **(b)** Track total "free mints awarded against this CLAWD position" by
  summing free mints across *all* wallets that ever held the CLAWD — too
  expensive on-chain;
- **(c)** Cap *total* free mints supply (e.g. only first 2,000 token IDs are
  free-eligible), so even if cycling works the contract still earns on the
  remaining 8,000;
- **(d)** Document loudly that the cap is "per wallet" and the real cap on
  free mints is just `MAX_SUPPLY` shared by all CLAWD holders (this is the
  current state — at minimum it must be in the README and the dApp).

(c) is the smallest contract change with a real economic effect. (a) is the
most correct fix.

---

## [M-3] Owner-controlled `clawdUsdPrice` has no bounds, no time-lock, and no event-rate-limit
**Severity:** Medium
**Category:** oracles / access-control
**Location:** `AiPunks.sol:208-211` (`setClawdUsdPrice`), `AiPunks.sol:71`

**Description:** `setClawdUsdPrice` accepts any `uint256` and writes it
synchronously. There is no upper bound, no per-block change limit, and no
time-lock. The owner can:

1. **Front-run buyers up:** see a `mint(quantity)` tx in the mempool,
   raise `clawdUsdPrice` first → buyer's `freeMintsEligible` jumps and the
   buyer mints free instead of paid (steals revenue from himself /
   collection if owner is malicious from buyer perspective);
2. **Front-run buyers down:** lower `clawdUsdPrice` to 0 right before a
   buyer's tx → buyer pays full ETH for what should have been a free mint;
3. **Set absurd prices:** e.g. `1e30` → every CLAWD holder of 1 token
   immediately overflows the `eligible > MAX_FREE_PER_WALLET` clamp and
   gets 20 free mints. With no cap on `clawdBal * price`, a sufficiently
   large value can also revert in the multiplication and brick mint for
   that user (see L-1).

Combined with the owner also controlling `mintPrice`, the owner can drain
the entire mint economics in either direction with a single tx.

**Recommendation:** Add a hard ceiling check: `require(newPrice <= MAX_PRICE)`
where `MAX_PRICE` is e.g. `100e18` ($100 / CLAWD — comfortably above any
realistic CLAWD valuation). Optionally apply a 24-hour delay on price
changes via a small timelock (store `pendingClawdUsdPrice` + `effectiveAt`).
At minimum, document the unilateral owner power as a centralization risk in
the README.

---

## [L-1] Unbounded `clawdBal * clawdUsdPrice` can overflow and DoS `mint`/`freeMintsEligible` for a specific holder
**Severity:** Low
**Category:** precision-math
**Location:** `AiPunks.sol:175` (`freeMintsEligible`)

**Description:** `(clawdBal * price) / 1e36` is evaluated *before* the divide
in Solidity. CLAWD's current total supply is `~1e29` (9.998e28). If the
owner ever sets `clawdUsdPrice = 1e48` (absurd, but unbounded — see M-3),
the multiplication `clawdBal * price` for a holder of even a moderate slice
(e.g. `1e28`) yields `1e76`, dangerously close to `2^256 - 1 ≈ 1.158e77`.
A holder with `1e29` and a price of `1e48` overflows and the call reverts.

This is academic given M-3's recommended bound, but worth noting:
`freeMintsEligible` is a `view` called by the dApp, by `mint()`, and likely
by external integrations — a revert there hard-stops minting for the
affected wallet.

**Recommendation:** Add the M-3 bound on `clawdUsdPrice`. As belt-and-
suspenders, switch to `Math.mulDiv(clawdBal, price, 1e36)` from
`@openzeppelin/contracts/utils/math/Math.sol`, which is both cheaper at the
margin and overflow-safe up to `2^512`.

---

## [L-2] `mint(quantity)` has no per-call upper bound — single-tx gas-DoS / wasted gas for the caller
**Severity:** Low
**Category:** dos
**Location:** `AiPunks.sol:124-157` (`mint`)

**Description:** The mint loop runs `quantity` iterations, each of which
calls `_safeMint` (SSTORE for ownership + IERC721Receiver callback if the
recipient is a contract). On Base (~150M gas / block) and with ERC721 mint
costs of ~70-90k gas per token plus a callback, a `mint(2000)` from an EOA
will silently exhaust the block gas limit and revert. The caller wastes
gas; the contract is unaffected. Still, an explicit cap (e.g. `MAX_BATCH = 50`)
would (a) give a clean revert message and (b) let the dApp UI surface it.

**Recommendation:**
```solidity
uint256 public constant MAX_BATCH = 50;
if (quantity > MAX_BATCH) revert BatchTooLarge();
```

---

## [L-3] Refund failure reverts the whole mint — small UX footgun for contract-receivers that overpay
**Severity:** Low
**Category:** general
**Location:** `AiPunks.sol:151-156` (refund block in `mint`)

**Description:** If `msg.sender` is a contract whose `receive()` reverts AND
they overpaid, the entire `mint` reverts with `RefundFailed()`. The contract
isn't bricked — they simply must send `msg.value == required` exactly. But
the failure mode is non-obvious and waste­s the caller's gas.

EOAs are unaffected (no `receive()` to revert).

**Recommendation:** Either (a) require exact payment (`if (msg.value != required) revert`) and remove the refund path entirely, or (b) keep the refund and instead credit failed refunds to a `pendingWithdrawals[msg.sender]` mapping. Status quo is acceptable but worth a one-line comment.

---

## [L-4] `setRoyalty` has no bounds — owner can set up to 100% royalty
**Severity:** Low
**Category:** access-control
**Location:** `AiPunks.sol:213-215` (`setRoyalty`)

**Description:** OZ's `_setDefaultRoyalty` reverts only if `feeNumerator > _feeDenominator()` (10000 = 100%). The contract therefore lets the owner set royalties up to 100%, which most marketplaces will simply ignore (most cap at 10% and many no longer enforce royalties at all). Not a fund-loss issue, but a UX footgun.

**Recommendation:** Add a sanity cap: `require(feeNumerator <= 1000, "max 10%");` Or keep open and trust the owner — but at minimum emit an event for off-chain monitoring (currently `_setDefaultRoyalty` does not emit).

---

## [I-1] Owner can change `mintPrice` arbitrarily, including to zero
**Severity:** Info
**Category:** access-control / centralization
**Location:** `AiPunks.sol:198-201` (`setMintPrice`)

The owner can set `mintPrice = 0` at any time, making the entire collection free; or raise it 100x mid-sale. Standard Ownable centralization risk; document, don't fix.

---

## [I-2] Owner can withdraw all proceeds at any time; no escrow / vesting
**Severity:** Info
**Category:** access-control / centralization
**Location:** `AiPunks.sol:218-222` (`withdraw`)

By design. Document in README.

---

## [I-3] `_safeMint` triggers `onERC721Received` — minor reentrancy surface, mitigated by `nonReentrant`
**Severity:** Info
**Category:** erc721
**Location:** `AiPunks.sol:145-147` (mint loop)

`_safeMint` invokes the receiver's `onERC721Received` callback before the
function returns. State (`totalMinted`, `usedFreeMints`) is fully updated
before the loop starts, and `nonReentrant` blocks recursive `mint()`. The
callback can still call other `view`/`pure` functions or transfer the just-
minted token to another address mid-mint, but neither breaks any invariant.
No action required; called out for completeness.

---

## [I-4] Spec deviation: free mint counts truncate cents (intentional)
**Severity:** Info
**Category:** precision-math / spec-compliance
**Location:** `AiPunks.sol:175-177`

`usdValue / USD_PER_FREE_MINT` floors. Holders with $999.99 USD of CLAWD
get 0 free mints, $1,000.00 gets 1, $1,999.99 gets 1, $2,000.00 gets 2.
This matches the natural reading of "Every $1,000 USD held = 1 free mint";
flagged so Stage 4 confirms intent and adds a code comment.

---

## [I-5] `clawdUsdPrice = 0` default disables free mints — owner must call `setClawdUsdPrice` post-deploy
**Severity:** Info
**Category:** spec-compliance / operational
**Location:** `AiPunks.sol:71` (state default)

Documented in the contract NatSpec. Until the owner posts a price, every
mint is the full 0.069 ETH. This is a deliberate Option-B oracle choice
(see contract comments) and the right call given the thin $CLAWD/WETH
liquidity on Base — but Stage 5 (deploy) should immediately follow up with
a price-setting tx, and the dApp must surface "free mints currently disabled"
when `clawdUsdPrice == 0`.

---

## [I-6] No off-chain "free mints used" event for indexers
**Severity:** Info
**Category:** general
**Location:** `AiPunks.sol:86`, `AiPunks.sol:149`

The single `Minted(buyer, quantity, freeUsed, paid)` event is sufficient,
but consider adding `event UsedFreeMintsUpdated(address indexed buyer, uint256 newTotal)`
for indexers / leaderboards. Cosmetic.

---

# Items explicitly checked and PASS

The following common ERC-721 / OZ-v5 footguns were inspected and are clean:

- **`_safeMint` ID range:** IDs are `1..totalMinted` — no zero-id, no
  collision (`startId = totalMinted; totalMinted += quantity;` then loop
  emits `startId+1 ... startId+quantity`). Cap enforced *before* state
  changes.
- **OZ v5 compatibility:** `Ownable(initialOwner)` constructor is correct
  (v5 removed the no-arg constructor). `_requireOwned(tokenId)` is the v5
  replacement for `_exists` + manual revert; correctly used in `tokenURI`.
  No `_beforeTokenTransfer` override (v5 uses `_update`); contract doesn't
  need to override either.
- **Constructor zero-address check:** `Ownable(address(0))` reverts via OZ;
  `_setDefaultRoyalty(receiver=0, ...)` also reverts via OZ. Both surface a
  clear error if `initialOwner == 0`.
- **Reentrancy:** `nonReentrant` on `mint` and `withdraw`; refund placed
  last in `mint`; CEI generally respected.
- **Supply cap:** `if (totalMinted + quantity > MAX_SUPPLY) revert` — checked
  before state change; cannot be bypassed via reentrancy thanks to
  `nonReentrant`.
- **Token URI:** `tokenURI(id)` reverts on non-existent ids via
  `_requireOwned`; returns empty string when base is unset (for the
  placeholder period); concatenates `<base><id>.json` correctly via
  `Strings.toString`.
- **Royalty:** `_setDefaultRoyalty(initialOwner, 500)` in constructor → 5%
  to client, matches spec.
- **CLAWD decimals confirmed 18** via on-chain `decimals()` call to
  `0x9f86dB9...6b07` on Base — math assumption holds.
- **No external `transferFrom` / approve flow on CLAWD:** contract only
  reads `balanceOf`. No approval-race, no allowance, no fee-on-transfer
  exposure.
- **No upgradeability / proxy / delegatecall:** standard direct-deployment.
- **No assembly / low-level calls** other than the two ETH `call`s, both
  with explicit boolean checks.

---

*End of report.*
