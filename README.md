# Ai Punks

10,000 AI-enhanced CryptoPunks. ERC-721 on Base. Powered by `$CLAWD`.

- **Live URL:** _TBD — IPFS deploy on Stage 9_
- **Contract:** [`0xb92632ce19bc7f3e86f672606000f9da31481a93`](https://basescan.org/address/0xb92632ce19bc7f3e86f672606000f9da31481a93) (verified)
- **Network:** Base (chain id 8453)
- **Owner / payout:** `0x68B8dD3d7d5CEdB72B40c4cF3152a175990D4599`

## Mint mechanics

- **Supply:** 10,000.
- **Mint price:** 0.005 ETH per token.
- **`$CLAWD`-gated free mints:** the first 2,000 mints are free for wallets holding **≥ $50 worth** of `$CLAWD` (token: [`0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07`](https://basescan.org/address/0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07)). One free mint per wallet, capped at a 2,000 global pool. The owner publishes the `$CLAWD/USD` price on-chain via `setClawdUsdPrice` (capped at `$1` per `$CLAWD` to bound spend). Free mints are claimed first when a wallet calls `mint(qty)` — `paid = qty - free`. No approvals required: it is pure ETH.
- **Royalties:** ERC-2981, 5% to the owner (cap 10%).
- **Reentrancy:** `mint` and `withdraw` are guarded; refunds use `call` with explicit failure reverts.

## Architecture decisions

- **Owner-set price oracle:** there is no live `$CLAWD/USD` feed on Base. Pulling from a DEX TWAP would mean trusting a single pool that an attacker can manipulate before a mint cycle. We chose an explicit owner-published price, capped at `$1`, so the worst case is the owner griefing themselves (zero free mints) instead of users overpaying.
- **2k global free-mint cap:** keeps the giveaway bounded - even if `$CLAWD` whales sybil 10k wallets, only 2k free tokens leave the pool.
- **No allowlist contract:** `$CLAWD` balance _is_ the allowlist - measured at mint time, not snapshot.
- **`_safeMint` in a loop:** OZ v5 ERC-721 + `nonReentrant` guard. The `Minted` event fires after all mints to keep the storage delta atomic.

## Run locally

```bash
yarn install
yarn chain                 # local anvil
yarn deploy                # deploys AiPunks to local
yarn start                 # frontend at http://localhost:3000
```

For a static IPFS-ready build:

```bash
cd packages/nextjs
NEXT_PUBLIC_IPFS_BUILD=true \
  NODE_OPTIONS="--require ./polyfill-localstorage.cjs" \
  yarn build
# output: packages/nextjs/out/
```

## Project layout

- `packages/foundry/` - Solidity, Foundry deploy scripts, audit artifacts under `audits/`.
- `packages/nextjs/` - Next.js App Router frontend (RainbowKit + Wagmi + Viem).
- `packages/nextjs/contracts/deployedContracts.ts` - auto-generated ABI + address.
- `packages/nextjs/contracts/externalContracts.ts` - `$CLAWD` ERC-20 on Base (read-only).

## Built for

[LeftClaw Job #83](https://leftclaw.services). Worker: `clawdbotatg`.
