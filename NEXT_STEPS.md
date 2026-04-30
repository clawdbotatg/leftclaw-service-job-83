# Ai Punks — Next Steps for the Client

This is a partial delivery. The on-chain mint contract and the mint dApp are live. Two pieces of follow-up work are out of the scope of a LeftClaw build job and need to be commissioned or completed separately by you.

## What's shipped

- ERC-721 contract `AiPunks` deployed and verified on Base — `0xb92632ce19bc7f3e86f672606000f9da31481a93`
- Owner is your wallet (`0x68B8dD3d7d5CEdB72B40c4cF3152a175990D4599`)
- Mint dApp on IPFS — `https://bafybeiapiqvf2ug5ysfsp64v5h6l4rkxvydvyod7evxedefcfjemp3kwou.ipfs.community.bgipfs.com/`
- Free-mint logic ($CLAWD-balance gated, 1 free mint per $1k held, capped at 20/wallet, 2,000 global cap) — fully on-chain
- 5% royalty (ERC-2981) routes to your wallet
- 21/21 Foundry tests passing
- Contract audited (Stage 3 audit at `audits/STAGE3_AUDIT.md`); all Critical/High/Medium fixes applied

## What's NOT shipped — and why

### 1. The 10,000 unique pixel-art PFPs

**Out of scope for a LeftClaw build worker.** Generating 10k unique 24×24 pixel-art images that fuse 87 original CryptoPunks traits with 20 new AI/Metaverse traits, gated by the rarity logic in your spec, is a creative-asset commission. It is a multi-week project for a pixel-art generator pipeline + curation, not a 1.5-hour software build.

**To complete the collection you need to:**
1. Commission an art generator (or build one) that produces 10,000 PNGs + 10,000 metadata JSONs honoring your trait distribution, rarity tiers, and bio-glow accents.
2. Upload images and metadata to IPFS (you can use bgipfs the same way this dApp was uploaded).
3. **Call `setBaseURI("ipfs://<metadata-CID>/")` on the contract from your owner wallet.** Token URIs will then resolve as `ipfs://<metadata-CID>/<tokenId>.json`.

Before `setBaseURI` is called, `tokenURI(tokenId)` returns an empty-prefix path. Minting still works; metadata just won't resolve until you set it.

### 2. The $CLAWD/USD price oracle

**The contract uses an owner-settable `clawdUsdPrice` rather than a TWAP.**

We considered a Uniswap V3 TWAP, but the only meaningfully-liquid $CLAWD/WETH pool on Base is concentrated in a single LP position — TWAPs on thin single-LP pools are cheap to grief into free mints. An owner-set price is simpler and safer for a low-cap community token.

**Default is `0`, which disables free mints.** Once you're ready to enable the $CLAWD-gating:
1. Compute `clawdUsdPrice` as USD per single $CLAWD, scaled to 18 decimals. Example: if 1 $CLAWD ≈ $0.001, set price = `1000000000000000` (1e15).
2. Call `setClawdUsdPrice(price)` from the owner wallet.
3. Update it whenever the market price moves materially. Hardcap is `1e18` (= $1.00 per $CLAWD) to prevent fat-finger overflows.

If you'd rather not maintain this manually, the next steps are: add a paid oracle (Chainlink, RedStone, etc.) once $CLAWD is supported, or stand up a UniV2 cumulative-price TWAP keeper. Either is its own project.

### 3. Custom domain + proper OG image

The IPFS URL works as the dApp, but social unfurls (Twitter, Farcaster, etc.) want absolute URLs for the OG image. To get clean unfurl previews:
- Point a custom domain (e.g. `aipunks.eth.link`, `aipunks.xyz`) at the IPFS gateway.
- Rebuild the frontend with `NEXT_PUBLIC_PRODUCTION_URL=https://your-domain` and reupload.

This does not affect the dApp's functionality.

## Other small things

- The contract has a `withdraw()` function — you (as owner) can pull paid-mint ETH at any time.
- The contract has a `setRoyalty(receiver, bps)` function — you can rotate the royalty receiver. Default is your wallet at 500 bps (5%).
- The contract has a `setMintPrice(uint256)` function — you can change the paid-mint price from the default 0.069 ETH if you want.
- All these admin functions are `onlyOwner`. If you ever transfer ownership, make sure the new owner is a payable address (i.e. not a contract that rejects ETH).

## Repo

`https://github.com/clawdbotatg/leftclaw-service-job-83`

Audit reports, response docs, and full source are in there.
