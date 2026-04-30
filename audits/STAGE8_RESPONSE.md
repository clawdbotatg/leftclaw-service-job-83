# Stage 8 — Frontend QA Fixes (Response)

- **Job:** LeftClaw Build #83 — *Ai Punks*
- **Repo:** `~/clawd/ethereum-servicer/builds/leftclaw-service-job-83`
- **Stage 7 source report:** `audits/STAGE7_QA.md`
- **Issues addressed:** `#4`, `#5`, `#6`, `#7`, `#8` (label `frontend-audit`, all `should-fix`)
- **Build verification:** `cd packages/nextjs && NEXT_PUBLIC_IPFS_BUILD=true NODE_OPTIONS="--require ./polyfill-localstorage.cjs" yarn build` → exit 0
- **Stop conditions:** contract NOT modified, `deployedContracts.ts` NOT touched, no IPFS upload (Stage 9 owns that)

---

## Itemised response

### Issue #6 — F1 (HIGH): Static copy advertised wrong mint price + free-mint threshold

**Status:** Fixed.

The deployed contract has `mintPrice = 0.069 ether`, `MAX_FREE_PER_WALLET = 20`, `USD_PER_FREE_MINT = 1000`. Three source files contained out-of-date copy.

| File | Before | After |
|---|---|---|
| `packages/nextjs/app/page.tsx:298` | "Holding ≥ $50 of $CLAWD gets 1 free mint (max 1 per wallet, 2,000 global cap)." | "Each $1,000 USD of $CLAWD held grants 1 free mint (up to 20 free mints per wallet, 2,000 global cap)." |
| `packages/nextjs/app/layout.tsx:18` | "…0.005 ETH otherwise." | "…0.069 ETH otherwise." |
| `README.md:13-14` | "Mint price: 0.005 ETH per token." / "≥ $50 worth … One free mint per wallet" | "Mint price: 0.069 ETH per token." / "≥ $1,000 USD worth of $CLAWD per free mint … Up to 20 free mints per wallet" |

The dynamic on-page numbers (MINT PRICE stat card, "Mint N for X ETH" button, eligible/used rows) already read from the contract via `useScaffoldReadContract` (no change needed). Only the static copy was wrong; it's now consistent with on-chain values.

**Verification grep on prerendered HTML (`packages/nextjs/out/index.html`):**

```
grep -E "(0\.005|\$50|max 1 per|localhost:3000|Scaffold-ETH 2)" out/index.html
# → no matches
grep "0.069 ETH" out/index.html → present in <meta description>
```

### Issue #4 — S2: OG image was `http://localhost:3000/thumbnail.jpg` in static export

**Status:** Fixed.

Refactored `packages/nextjs/utils/scaffold-eth/getMetadata.ts` so the absolute base URL resolution prefers (in order): `NEXT_PUBLIC_PRODUCTION_URL` → `VERCEL_PROJECT_PRODUCTION_URL` → (only when `NEXT_PUBLIC_IPFS_BUILD === "true"`) the placeholder `https://aipunks.eth.link` → localhost (dev only). For Stage 9 the operator can pass `NEXT_PUBLIC_PRODUCTION_URL=https://<CID>.ipfs.community.bgipfs.com` to overwrite the placeholder with the real gateway URL.

**No real key/URL committed.** The placeholder is a public DNS name that does not need to resolve — it just keeps the rendered tags non-localhost.

`packages/nextjs/.env.example` updated to document `NEXT_PUBLIC_PRODUCTION_URL` and `NEXT_PUBLIC_IPFS_BUILD`.

**Verification grep on prerendered HTML:**

- Before (Stage 7): `<meta property="og:image" content="http://localhost:3000/thumbnail.jpg"/>`
- After (Stage 8): `<meta property="og:image" content="https://aipunks.eth.link/thumbnail.jpg"/>` (also `out/debug/index.html`)

Stage 9 should re-build with `NEXT_PUBLIC_PRODUCTION_URL=https://<final-cid>.ipfs.community.bgipfs.com` set so the meta tags point at the actual live URL.

### Issue #5 — S7: Mobile deep-link was `window.focus()`, not a wallet URL

**Status:** Fixed by removing the meaningless poke.

`packages/nextjs/app/page.tsx:132-141` previously fired a `setTimeout(() => window.focus(), 2000)` after the write resolved. As the audit noted, this does not switch a mobile user to their wallet app — it's a no-op. RainbowKit + WalletConnect already handle wallet-app deep-linking on mobile (the standard SE-2 / RainbowKit flow). Removed the dead code and replaced it with a comment that documents the expected mobile UX.

We do not implement a custom `metamask://` / `rainbow://` deep link because (a) the active connector isn't reliably introspected from `useScaffoldWriteContract`, and (b) RainbowKit's WalletConnect flow already produces the correct deep link on mobile when the user connects via the WalletConnect QR.

### Issue #7 — F2: `/debug` page metadata mentioned Scaffold-ETH 2

**Status:** Fixed.

`packages/nextjs/app/debug/page.tsx:7` description changed from
*"Debug your deployed 🏗 Scaffold-ETH 2 contracts in an easy way"* to
*"Read and write all functions on the deployed Ai Punks contract directly from the browser."*

Verified `out/debug/index.html` contains the new text and no `Scaffold-ETH 2` reference.

### Issue #8 — F3: Bare `http()` fallback transport in `wagmiConfig`

**Status:** Fixed.

Rewrote the `client` factory in `packages/nextjs/services/web3/wagmiConfig.tsx`:

- Priority 1: explicit `scaffoldConfig.rpcOverrides[chainId]`
- Priority 2: Alchemy URL via `getAlchemyHttpUrl(chainId)` (uses `NEXT_PUBLIC_ALCHEMY_API_KEY`; falls back to scaffold's shared default key, which is then ranked behind any other transport)
- Priority 3 (mainnet only): `https://mainnet.rpc.buidlguidl.com` for ENS / price reads
- Last-ditch only (no URL configured for the chain): bare `http()` — guarded behind a length check so it never coexists with Alchemy/override

For the target network (Base), this means the fallback chain is `[Alchemy]` (own key) or `[Alchemy(default)]` (shared key). No bare `http()` for Base — the public RPC is no longer reached on the happy path.

**No real Alchemy key committed.** `scaffold.config.ts` still ships SE-2's shared default key as a developer fallback (this was already in the repo from Stage 1; not changed here). The recommended path for a production launch is to set `NEXT_PUBLIC_ALCHEMY_API_KEY` at build time, which `.env.example` now documents.

---

## Build / verification

```
cd packages/nextjs
NEXT_PUBLIC_IPFS_BUILD=true NODE_OPTIONS="--require ./polyfill-localstorage.cjs" yarn build
# exit 0
ls -la out/index.html      # 20,546 bytes
grep -E "(0\.005|\$50|max 1 per|localhost:3000|Scaffold-ETH 2)" out/index.html
# → no matches
grep -E "(0\.005|\$50|max 1 per|localhost:3000|Scaffold-ETH 2)" out/debug/index.html
# → no matches
```

The 0.005 strings remaining anywhere under `out/` are inside SVG path coordinates in two icon chunks (e.g. `M…0.0058…`) — not user-facing copy.

## Stop conditions honoured

- Contract NOT modified.
- `packages/nextjs/contracts/deployedContracts.ts` NOT modified.
- No IPFS upload.

## Files changed

- `packages/nextjs/app/page.tsx` — copy fix + removed dead `window.focus()` setTimeout
- `packages/nextjs/app/layout.tsx` — meta description price corrected
- `packages/nextjs/app/debug/page.tsx` — Scaffold-ETH 2 mention rewritten
- `packages/nextjs/services/web3/wagmiConfig.tsx` — RPC fallback policy fixed
- `packages/nextjs/utils/scaffold-eth/getMetadata.ts` — non-localhost OG base URL
- `packages/nextjs/.env.example` — documents new env vars
- `README.md` — mint mechanics paragraph corrected
