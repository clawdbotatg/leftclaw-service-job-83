# Stage 7 — Frontend QA Audit (READ-ONLY)

- **Job:** LeftClaw Build #83 — *Ai Punks*
- **Repo:** `~/clawd/ethereum-servicer/builds/leftclaw-service-job-83`
- **Frontend root:** `packages/nextjs/`
- **Static export:** `packages/nextjs/out/`
- **Deployed contract:** `AiPunks @ 0xb92632ce19bc7f3e86f672606000f9da31481a93` (Base, chain 8453, **verified — Exact Match** on Basescan)
- **External token:** `CLAWD @ 0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07`

Method: source-trace, not pattern-match. Every reference below cites a `file:line`.

---

## 1. Ship-blockers

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Wallet connect shows a **button**, not text | **PASS** | `app/page.tsx:205` renders `<RainbowKitCustomConnectButton/>` inside the not-connected branch. No "please connect" paragraph as primary CTA. Header also has it (`components/Header.tsx:97`). |
| 2 | Wrong network shows a **Switch button** (one CTA at a time) | **PASS** | `app/page.tsx:207-219` — `wrongNetwork` branch renders a single `btn btn-primary` "Switch to Base" button calling `switchChain({ chainId: targetNetwork.id })`. Mint widget body is gated on `connectedAddress && !wrongNetwork`. |
| 3 | Mint button disabled through full block confirmation + cooldown | **PASS** | `app/page.tsx:148-149` — `buttonDisabled = isMining \|\| cooldownActive \|\| ...`. `isMining` comes from `useScaffoldWriteContract` (`hooks/scaffold-eth/useScaffoldWriteContract.ts:76,109,144`) which sets `isMining=true` at handler entry and clears it in `finally{}` after `useTransactor` (`hooks/scaffold-eth/useTransactor.tsx`) awaits `publicClient.waitForTransactionReceipt`. `cooldownActive` flips on inside `onBlockConfirmation` (`app/page.tsx:121-129`), driven by a 250ms `setInterval` clock (`app/page.tsx:73-76`). The 4 s `COOLDOWN_MS` keeps the button locked through the cache-refetch window. Both states cover both gaps. |
| 4 | Mint flow traced end-to-end | **PASS** | See Section 4 below. `value = mintPrice * paidQty` matches contract; spender semantics N/A (mint is pure ETH, no ERC-20 approve). All custom errors covered. |
| 5 | Contract verified on Basescan | **PASS** | `curl https://basescan.org/address/0xb92632ce19bc7f3e86f672606000f9da31481a93` returns "Contract Source Code Verified (Exact Match)". |
| 6 | SE2 footer branding (Fork-me, BG, Support, nativeCurrencyPrice) removed | **PASS** | `components/Footer.tsx:1-48` — only Ai Punks brand, contract `<Address/>`, and a single LeftClaw Job #83 link. `SwitchTheme` retained, `Faucet` is gated on `isLocalNetwork` (Base mainnet ≠ hardhat → not rendered). No `nativeCurrencyPrice`, no `BuidlGuidl`, no `Fork me` link. |
| 7 | Tab title not `"%s \| Scaffold-ETH 2"` | **PASS** | `utils/scaffold-eth/getMetadata.ts:11` → `titleTemplate = "%s \| Ai Punks"`. Static HTML confirms `<title>Ai Punks</title>` (root) and `<title>Debug Contracts \| Ai Punks</title>` (debug). |
| 8 | README replaced (project root) | **PASS** | `README.md:1-54` is fully Ai Punks-specific (mint mechanics, architecture decisions, project layout, LeftClaw #83 attribution). No SE2 template README content. *Note: contains a numerical inaccuracy — see Section 3, F1.* |
| 9 | Favicon replaced (not SE2 default) | **PASS** | `public/favicon.png` md5=`31398c6ba0444ae773fdcb272dc616fd`, 64x64 PNG — not SE2 default (which is the scaffold logo). The static export references `/favicon.png` from this file. |
| 10 | Burner wallet hidden on Base mainnet | **PASS** | `scaffold.config.ts:41` → `burnerWalletMode: "localNetworksOnly"`. `services/web3/wagmiConnectors.tsx:17-19` — `hasOnlyLocalTargetNetworks` is false because target is `chains.base`, so `showBurnerWallet=false`. |

**Ship-blockers: 10/10 PASS, 0 FAIL.**

---

## 2. Should-fix

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| S1 | Contract address shown via `<Address/>` | **PASS** | Hero: `app/page.tsx:191` (`<Address address={"0xb926…1A93"} chain={base}/>`). Footer: `components/Footer.tsx:37` reads from `useScaffoldContract({contractName: "AiPunks"})`. Both render the canonical `<Address/>` with blockie/explorer/copy. |
| S2 | OG image uses absolute URL (`NEXT_PUBLIC_PRODUCTION_URL` checked) | **FAIL** | Source logic in `utils/scaffold-eth/getMetadata.ts:3-9` is correct (checks `NEXT_PUBLIC_PRODUCTION_URL` first), but the **static export was built without that env var set** — `out/index.html` and `out/debug/index.html` both contain `<meta property="og:image" content="http://localhost:3000/thumbnail.jpg"/>`. Twitter image identical. This breaks every social unfurl. Stage 8 must rebuild with `NEXT_PUBLIC_PRODUCTION_URL` exported (placeholder `https://aipunks.eth.link` works; the live IPFS URL is fine too). |
| S3 | `--radius-field: 0.5rem` in BOTH theme blocks of `globals.css` | **PASS** | `styles/globals.css:41` (light) and `styles/globals.css:66` (dark). Both `0.5rem`, neither `9999rem`. |
| S4 | Token amounts shown with USD context (or explicit N/A) | **PASS — with caveat** | ETH mint price is shown in ETH only, no USD (no oracle integrated). `$CLAWD` balance is shown without USD because the only on-chain price is the owner-set value, which the UI already displays separately as "$CLAWD price (USD, owner-set)" — that is effectively the USD-context for the user's CLAWD holding (a derived calculation would be redundant). Marking PASS because: (a) ETH/USD on Base has no SE2-standard hook wired, (b) the owner-set CLAWD/USD price is rendered side-by-side, (c) the qty×ETH cost line is the actual transaction value the user signs. Could be improved by computing `clawdBalance * clawdUsdPrice` and showing the dollar value next to the balance — file as polish, not blocker. |
| S5 | Errors mapped to human-readable messages — ABI covers all error types in call chain | **PASS** | `deployedContracts.ts:845-1093` enumerates: `BatchTooLarge`, `MaxSupplyExceeded`, `Underpaid(required,sent)`, `RefundFailed`, `ZeroQuantity`, `PriceTooHigh`, `RoyaltyTooHigh`, `WithdrawFailed`, `ZeroAddress`, `ReentrancyGuardReentrantCall`, `OwnableUnauthorizedAccount`, `OwnableInvalidOwner`, all 8 OZ ERC721 custom errors (incl. `ERC721InvalidReceiver` thrown by `_safeMint` → `onERC721Received`), all 4 ERC2981 errors. Cross-checked against `AiPunks.sol:124-132` `error` block — every contract-defined error is in the ABI. `getParsedError` (`utils/scaffold-eth/getParsedError.ts`) decodes `ContractFunctionRevertedError.data.errorName` from this ABI; `useTransactor` invokes `getParsedErrorWithAllAbis` (sees both `deployedContracts` and `externalContracts` ABIs). Every revert reachable from `mint()` resolves to a name. |
| S6 | Phantom wallet present in RainbowKit list | **PASS** | `services/web3/wagmiConnectors.tsx:8,27` — `phantomWallet` imported and included alongside MetaMask, WalletConnect, Ledger, Base, Rainbow, Safe. |
| S7 | Mobile deep linking pattern (`setTimeout(openWallet, 2000)` after fire) | **FAIL — partial** | `app/page.tsx:132-141` does fire the TX *first* and uses a 2 s `setTimeout`, but it only calls `window.focus()` — **not a wallet deep link**. `window.focus()` does not switch a mobile user to their wallet app. The QA skill calls for an `openWallet` helper that detects the connector + WalletConnect session and navigates to the wallet's deep-link URL (`metamask://`, `rainbow://`, etc.). On a mobile user with WalletConnect this flow leaves them stranded — they have to manually re-open their wallet to sign. Severity: should-fix. |
| S8 | `appName` in `wagmiConnectors.tsx` is "Ai Punks" | **PASS** | `services/web3/wagmiConnectors.tsx:51` → `appName: "Ai Punks"`. Confirmed not `"scaffold-eth-2"`. |

**Should-fix: 6 PASS, 2 FAIL (S2 og:image, S7 mobile deep-link).**

---

## 3. Additional findings

**F1 — Mint price + free-mint description in static UI/README do not match deployed contract (HIGH PRIORITY for Stage 8).**

The deployed contract has `mintPrice = 0.069 ether` (verified on-chain — `cast call` returns `69000000000000000`), `MAX_FREE_PER_WALLET = 20`, `USD_PER_FREE_MINT = 1000`.

But the human-readable copy says otherwise:
- `app/page.tsx:298` — *"Holding ≥ $50 of $CLAWD gets 1 free mint (max 1 per wallet, 2,000 global cap)."* — wrong on every count except global cap. Truth: ≥ $1,000 of $CLAWD gets 1 free mint, max 20 per wallet.
- `app/layout.tsx:18` — meta description: *"…0.005 ETH otherwise."* — wrong, actual price is 0.069 ETH. Twitter/OG description inherits this.
- `README.md:13` — *"Mint price: 0.005 ETH per token."* — wrong.
- `README.md:14` — *"≥ $50 worth … One free mint per wallet"* — wrong.

The dynamic on-page numbers (MINT PRICE stat card, "Mint N for X ETH" button, eligible/used rows) all read from the contract and will show correctly. **Only the static copy is wrong.** This is a documentation bug, not a contract bug. Stage 8 should fix the strings.

**F2 — Scaffold-ETH 2 description string lingers on `/debug` page metadata.**

`app/debug/page.tsx:7` — *"Debug your deployed 🏗 Scaffold-ETH 2 contracts in an easy way"*. Renders into the `<meta name="description">` on `out/debug/index.html`. Should be updated to project-specific text.

**F3 — Bare `http()` fallback transport remains.**

`services/web3/wagmiConfig.tsx:20` includes `http()` (no URL) in the rpc fallback chain. Per `qa/SKILL.md` ("RPC & Polling Config"), this silently routes to the public RPC for the chain (`base.publicRpcUrls.default`), which is rate-limited. The Alchemy URL is appended (or prepended when an env API key is present), so this isn't a hard breakage — but on a high-traffic mint it can cause sporadic stale reads. Recommend dropping the bare `http()` entry. Should-fix.

**F4 — Default Alchemy API key is in source.**

`scaffold.config.ts:14` ships a public default key (`cR4WnXePioePZ5fFrnSiR`). It works, but Alchemy rate-limits shared keys. For an actual mint launch the deployer should set `NEXT_PUBLIC_ALCHEMY_API_KEY` at build time. Not a blocker for Stage 8 — flag for client awareness.

**F5 — `next.config.ts` IPFS gating is correct.**

`next.config.ts:16-24` correctly gates `output:"export"`, `trailingSlash:true`, `images.unoptimized:true` on `NEXT_PUBLIC_IPFS_BUILD === "true"`. Confirmed `out/` contains `/index.html`, `/debug/index.html`, `/404.html`, `/_next/static/...`.

**F6 — Static prerender produced real content.**

`out/index.html` contains the rendered hero ("Ai Punks", "10,000 AI-enhanced CryptoPunks. Powered by $CLAWD."), the three stat cards, the contract `<Address/>` (with blockie SVG inlined), the "Connect Wallet" button label, and the footer brand line. Not just an empty React shell. IPFS gateways will serve readable content even before client-side hydration.

**F7 — `app/blockexplorer/` is still in the `app/` tree.**

`app/blockexplorer/` still exists alongside `app/debug/` and `app/page.tsx`. Per CLAUDE.md "Disable blockexplorer for IPFS builds — rename `packages/nextjs/app/blockexplorer` to `app/_blockexplorer-disabled` before building." However, the build evidently succeeded — `out/` does **not** contain a `blockexplorer/` directory. Why: there is a sibling `packages/nextjs/_disabled-routes/blockexplorer/` directory and inspection suggests the routes were moved/copied. The static export proves it didn't crash. Marking informational only; no action required if subsequent IPFS builds remain clean.

**F8 — `vercel.json` present.**

`packages/nextjs/vercel.json` exists in repo. Build path is IPFS-only per spec, so the file is harmless but unused. Optional cleanup.

**F9 — `console.error(err)` in mint catch (`app/page.tsx:143`).**

Safe: it's a `console.error` swallow on user-rejected/reverted tx, not an info-level `console.log`. The `notification.error(...)` UX path runs from inside `useTransactor`. Acceptable.

**F10 — No real keys/secrets committed.**

`git grep` for 64-hex private keys finds only `0x2a87…6c6` in `packages/foundry/Makefile:8` — that is the well-known scaffold-eth-default Anvil dev key (never used on mainnet, public knowledge). All other 64-hex hits are tx hashes / block hashes inside `broadcast/Deploy.s.sol/8453/run-latest.json` (deployment artifacts — fine to commit). No `g.alchemy.com/v2/<KEY>` URLs in source.

**F11 — Polling interval is healthy.**

`scaffold.config.ts:20` → `pollingInterval: 3000` ms. Inside the responsive band (2–5 s) per `frontend-ux/SKILL.md` Rule 5.

**F12 — DaisyUI theme is used correctly.**

No hardcoded `bg-black` / `bg-zinc-900` / `bg-[#0a…]` on root wrappers. `app/page.tsx:157` uses `min-h-screen w-full` on a transparent `ap-scanline` div over body's `--color-base-200`. Both light and dark themes have hand-tuned palettes (`globals.css:21-71`). `SwitchTheme` toggle is preserved in the Footer.

**F13 — `BAILOUT_TO_CLIENT_SIDE_RENDERING` template in static HTML.**

The hero/footer DO statically render, but the React `Suspense` boundaries surrounding the wagmi providers correctly bail to client-side rendering — not a problem, expected for a wallet-aware app.

---

## 4. Mint-flow execution trace

Trace target: a connected user on Base, holding `Q_CLAWD` worth of `$CLAWD`, clicking *Mint* with `quantity = q`.

### Step 1 — Wallet connect

`app/page.tsx:200-206`. If `connectedAddress` is undefined → render `<RainbowKitCustomConnectButton/>` and a sentence. Single CTA. Pass.

### Step 2 — Wrong-network gate

`app/page.tsx:22`: `wrongNetwork = Boolean(connectedAddress) && walletChainId !== targetNetwork.id`. `targetNetwork.id = 8453` (Base). Branch at `:207-219` renders `<button … onClick={() => switchChain({ chainId: 8453 })}>Switch to Base</button>`. Disabled while `isSwitching`. Single CTA. Pass.

### Step 3 — Reads pre-populate

While on Base + connected:

- `totalMinted` ← `AiPunks.totalMinted()` (`page.tsx:25`)
- `mintPrice` ← `AiPunks.mintPrice()` (`:29`) → resolves to `69000000000000000n` (0.069 ETH) on-chain
- `freeRemainingGlobal` ← `AiPunks.freeMintsRemainingGlobal()` (`:33`)
- `clawdUsdPrice` ← `AiPunks.clawdUsdPrice()` (`:37`) — currently 0 on the deployed contract (free mints disabled until owner sets)
- `clawdBalance` ← `CLAWD.balanceOf(connectedAddress)` from external contract registration (`:42-46`). Spender = `0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07`. Confirmed in `externalContracts.ts:17`. ABI exposes `balanceOf(address) view returns (uint256)` (`externalContracts.ts:19-25`).
- `eligibleFreeMints` ← `AiPunks.freeMintsEligible(addr)` (`:47`)
- `freeRemainingForUser` ← `AiPunks.freeMintsRemaining(addr)` (`:52`)
- `usedFreeMints` ← `AiPunks.usedFreeMints(addr)` (`:57`)

### Step 4 — UI math vs contract math

**UI (`page.tsx:99-108`):**
```ts
const free = qty < userFree ? qty : userFree;          // min(q, walletRemaining)
const freeCapped = free < globalFree ? free : globalFree; // further min with globalRemaining
const paid = qty - freeCapped;
const cost = mintPrice * paid;
```

**Contract (`AiPunks.sol:166-176`):**
```sol
uint256 eligible = freeMintsEligible(msg.sender);
uint256 used = usedFreeMints[msg.sender];
uint256 walletRemaining = eligible > used ? eligible - used : 0;
uint256 globalRemaining = MAX_FREE_MINTS - totalFreeMintsUsed;
uint256 remaining = walletRemaining < globalRemaining ? walletRemaining : globalRemaining;
uint256 freeUsed = quantity < remaining ? quantity : remaining;
uint256 paidQty = quantity - freeUsed;
uint256 required = paidQty * mintPrice;
```

The UI reads `freeRemainingForUser` (which itself is `freeMintsRemaining(account)` — the contract view at `AiPunks.sol:232-238` already returns `min(walletRemaining, globalRemaining)`). The UI then re-applies `min(globalRemaining)` on top. That is a **harmless double-application of the same clamp** — the inner read is already bounded by the outer value. Math is **identical to the contract**. No divergence; underpayment impossible because UI's `cost` equals contract's `required`.

Caveat: between UI read and tx send, a different wallet's mint could exhaust `globalRemaining`, in which case the UI's `paid` would be too low → contract reverts with `Underpaid(required, sent)`. That is the correct, expected behaviour and the error decodes via `getParsedError` (ABI entry at `deployedContracts.ts:1063-1078`).

### Step 5 — `value` on the write call

`page.tsx:114-119`:
```ts
await writeAiPunks({
  functionName: "mint",
  args: [BigInt(quantity)],
  value: totalCost,
});
```

`totalCost = mintPrice * paidQty`. Matches contract's `required = paidQty * mintPrice`. Pass.

### Step 6 — Errors reachable from `mint()` and ABI coverage

Walking `AiPunks.mint(...)`:

| Reachable revert | In ABI? |
|---|---|
| `ZeroQuantity()` | yes (`deployedContracts.ts:1090`) |
| `BatchTooLarge()` | yes (`:846`) |
| `MaxSupplyExceeded()` | yes (`:1018`) |
| `Underpaid(required, sent)` | yes (`:1063-1078`) |
| `RefundFailed()` | yes (`:1054`) |
| `ReentrancyGuardReentrantCall()` | yes (`:1049`) |
| OZ `ERC721InvalidReceiver(receiver)` thrown by `_safeMint → onERC721Received` to a contract that doesn't return the magic selector | yes (`:984-993`) |

All custom errors decode to a name. `getParsedError` (`utils/scaffold-eth/getParsedError.ts:23-26`) renders `ErrorName(args)` for non-`Error` reverts.

### Step 7 — Disable / cooldown lifecycle

- Click → `onMint` runs → `useScaffoldWriteContract.sendContractWriteAsyncTx` sets `isMining=true` → button shows "Minting…", disabled.
- Simulate → wallet popup → user signs → `useTransactor` awaits `waitForTransactionReceipt` (block confirmation).
- On receipt (`onBlockConfirmation`): `setCooldownUntil(Date.now()+4000)` and refetch six on-chain values; `notification.success(...)` fires; button shows "Confirming…" until `now < cooldownUntil` flips.
- After `await` returns → `finally{}` clears `isMining`. The 4 s cooldown still keeps the button disabled while the refetched cache propagates.
- After cooldown elapses → button re-enables with the new totals.

End-to-end coverage of both the wallet→hash gap (covered by `isMining`) and the confirm→cache gap (covered by `cooldownActive`). Pass.

### Step 8 — Mobile deep-link nudge

`page.tsx:132-141` is reached after `await writeAiPunks(...)` resolves. Calls `window.focus()` 2 s after the user signs. **This is a focus poke, not a wallet deep-link.** A WalletConnect mobile user is not redirected to their wallet app. Mark as S7 FAIL — partial credit because the *pattern* (fire first, delay 2 s, then nudge) is correct, but the action lacks a `metamask://` / `rainbow://` deep-link.

### Step 9 — Refund path (informational)

If `msg.value > required`, contract refunds via `payable(msg.sender).call{value: refund}("")` (`AiPunks.sol:195-199`). UI never overpays (`totalCost == required`), so the refund branch never fires from the dApp's mint flow. No bug, just noting the refund is dead code unless someone hand-crafts the tx.

---

## Final verdict

- **Ship-blockers:** 10/10 PASS.
- **Should-fix:** 6/8 PASS, 2 FAIL (S2 og:image, S7 mobile deep-link).
- **Additional findings:** F1 is the most user-visible — static copy says 0.005 ETH and "$50 → 1 free mint", contract says 0.069 ETH and "$1,000 → 1 free mint, 20 per wallet". Stage 8 must align the strings.

**Verdict: READY for Stage 8 (no ship-blocker FAILs).** Stage 8 should fix S2, S7, F1, F2, F3 before IPFS upload. Once those are addressed and a fresh `out/` is built with `NEXT_PUBLIC_PRODUCTION_URL` set, the bundle is ready for Stage 9 deploy.

No source files modified by this audit.
