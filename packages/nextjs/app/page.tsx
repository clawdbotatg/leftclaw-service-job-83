"use client";

import { useEffect, useMemo, useState } from "react";
import { Address } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { formatEther, formatUnits } from "viem";
import { base } from "viem/chains";
import { useAccount, useSwitchChain } from "wagmi";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-eth";
import { useScaffoldReadContract, useScaffoldWriteContract, useTargetNetwork } from "~~/hooks/scaffold-eth";
import { notification } from "~~/utils/scaffold-eth";

const MAX_SUPPLY = 10_000n;
const MAX_FREE_MINTS = 2_000n;
const UI_MAX_PER_TX = 10;
const COOLDOWN_MS = 4_000;

const Home: NextPage = () => {
  const { address: connectedAddress, chainId: walletChainId } = useAccount();
  const { switchChain, isPending: isSwitching } = useSwitchChain();
  const { targetNetwork } = useTargetNetwork();
  const wrongNetwork = Boolean(connectedAddress) && walletChainId !== targetNetwork.id;

  // ---- on-chain reads ----
  const { data: totalMinted, refetch: refetchTotal } = useScaffoldReadContract({
    contractName: "AiPunks",
    functionName: "totalMinted",
  });
  const { data: mintPrice } = useScaffoldReadContract({
    contractName: "AiPunks",
    functionName: "mintPrice",
  });
  const { data: freeRemainingGlobal, refetch: refetchFreeGlobal } = useScaffoldReadContract({
    contractName: "AiPunks",
    functionName: "freeMintsRemainingGlobal",
  });
  const { data: clawdUsdPrice } = useScaffoldReadContract({
    contractName: "AiPunks",
    functionName: "clawdUsdPrice",
  });

  const { data: clawdBalance } = useScaffoldReadContract({
    contractName: "CLAWD",
    functionName: "balanceOf",
    args: [connectedAddress],
  });
  const { data: eligibleFreeMints, refetch: refetchEligible } = useScaffoldReadContract({
    contractName: "AiPunks",
    functionName: "freeMintsEligible",
    args: [connectedAddress],
  });
  const { data: freeRemainingForUser, refetch: refetchUserRemaining } = useScaffoldReadContract({
    contractName: "AiPunks",
    functionName: "freeMintsRemaining",
    args: [connectedAddress],
  });
  const { data: usedFreeMints, refetch: refetchUsedFree } = useScaffoldReadContract({
    contractName: "AiPunks",
    functionName: "usedFreeMints",
    args: [connectedAddress],
  });

  // ---- write ----
  const { writeContractAsync: writeAiPunks, isMining } = useScaffoldWriteContract({
    contractName: "AiPunks",
  });

  // local state
  const [quantity, setQuantity] = useState(1);
  const [cooldownUntil, setCooldownUntil] = useState(0);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(t);
  }, []);

  const remainingSupply = useMemo(() => {
    if (totalMinted === undefined) return undefined;
    if ((totalMinted as bigint) >= MAX_SUPPLY) return 0n;
    return MAX_SUPPLY - (totalMinted as bigint);
  }, [totalMinted]);

  const maxQty = useMemo(() => {
    let cap = UI_MAX_PER_TX;
    if (remainingSupply !== undefined) {
      const cappedRemaining = remainingSupply > BigInt(UI_MAX_PER_TX) ? BigInt(UI_MAX_PER_TX) : remainingSupply;
      cap = Math.min(cap, Number(cappedRemaining));
    }
    return Math.max(1, cap);
  }, [remainingSupply]);

  // clamp quantity to maxQty when it changes
  useEffect(() => {
    setQuantity(q => Math.min(Math.max(1, q), maxQty));
  }, [maxQty]);

  // free vs paid breakdown for the current quantity
  const { freeQty, paidQty, totalCost } = useMemo(() => {
    const qty = BigInt(quantity);
    const userFree = (freeRemainingForUser as bigint | undefined) ?? 0n;
    const globalFree = (freeRemainingGlobal as bigint | undefined) ?? 0n;
    const free = qty < userFree ? qty : userFree;
    const freeCapped = free < globalFree ? free : globalFree;
    const paid = qty - freeCapped;
    const cost = mintPrice !== undefined ? (mintPrice as bigint) * paid : 0n;
    return { freeQty: freeCapped, paidQty: paid, totalCost: cost };
  }, [quantity, freeRemainingForUser, freeRemainingGlobal, mintPrice]);

  // ---- handlers ----
  const onMint = async () => {
    if (!connectedAddress) return;
    try {
      await writeAiPunks(
        {
          functionName: "mint",
          args: [BigInt(quantity)],
          value: totalCost,
        },
        {
          onBlockConfirmation: () => {
            setCooldownUntil(Date.now() + COOLDOWN_MS);
            void refetchTotal();
            void refetchFreeGlobal();
            void refetchEligible();
            void refetchUserRemaining();
            void refetchUsedFree();
            notification.success(`Minted ${quantity} Ai Punk${quantity === 1 ? "" : "s"}`);
          },
        },
      );
      // mobile deep-link nudge: poke the wallet UI back to foreground after submit
      if (typeof window !== "undefined") {
        setTimeout(() => {
          try {
            window.focus();
          } catch {
            // ignore
          }
        }, 2000);
      }
    } catch (err) {
      console.error(err);
    }
  };

  const cooldownActive = now < cooldownUntil;
  const buttonDisabled =
    isMining || cooldownActive || quantity < 1 || (remainingSupply !== undefined && remainingSupply === 0n);

  const fmt = (v: bigint | undefined, decimals = 18, max = 4) =>
    v === undefined ? "—" : Number(formatUnits(v, decimals)).toLocaleString(undefined, { maximumFractionDigits: max });
  const fmtEth = (v: bigint | undefined, max = 5) =>
    v === undefined ? "—" : Number(formatEther(v)).toLocaleString(undefined, { maximumFractionDigits: max });

  return (
    <div className="ap-scanline min-h-screen w-full">
      <div className="flex flex-col items-center pt-12 pb-20 px-5">
        {/* Hero */}
        <section className="text-center max-w-2xl">
          <p className="text-xs ap-pixel tracking-widest text-base-content/60 mb-2">ERC-721 · BASE · 10,000 SUPPLY</p>
          <h1 className="ap-pixel text-6xl md:text-7xl font-bold leading-tight m-0">
            <span className="ap-glow">Ai</span> Punks
          </h1>
          <p className="text-base md:text-lg text-base-content/80 mt-4">
            10,000 AI-enhanced CryptoPunks. Powered by <span className="ap-pixel ap-glow">$CLAWD</span>.
          </p>
        </section>

        <div className="ap-divider w-full max-w-3xl my-8" />

        {/* Live stats */}
        <section className="grid grid-cols-1 md:grid-cols-3 gap-4 w-full max-w-3xl">
          <StatCard
            label="MINTED"
            value={totalMinted !== undefined ? `${(totalMinted as bigint).toString()} / ${MAX_SUPPLY.toString()}` : "—"}
          />
          <StatCard label="MINT PRICE" value={`${fmtEth(mintPrice as bigint | undefined)} ETH`} />
          <StatCard
            label="FREE MINTS LEFT"
            value={
              freeRemainingGlobal !== undefined
                ? `${(freeRemainingGlobal as bigint).toString()} / ${MAX_FREE_MINTS.toString()}`
                : "—"
            }
          />
        </section>

        <div className="mt-4 flex flex-col items-center gap-1">
          <span className="text-xs text-base-content/60 ap-pixel">CONTRACT</span>
          <Address address={"0xb92632ce19bc7f3e86f672606000f9da31481a93"} chain={base} />
        </div>

        <div className="ap-divider w-full max-w-3xl my-10" />

        {/* Mint widget */}
        <section className="w-full max-w-xl ap-card rounded-box p-6 md:p-8 bg-base-100/60">
          <h2 className="ap-pixel text-2xl m-0 mb-4">Mint</h2>

          {!connectedAddress ? (
            <div className="flex flex-col items-center gap-3 py-4">
              <p className="text-center text-base-content/70 m-0">
                Connect a wallet to see your $CLAWD balance and free-mint allowance.
              </p>
              <RainbowKitCustomConnectButton />
            </div>
          ) : wrongNetwork ? (
            <div className="flex flex-col items-center gap-3 py-4">
              <p className="text-center text-base-content/70 m-0">
                Wrong network. Ai Punks lives on <span className="ap-pixel">Base</span>.
              </p>
              <button
                className="btn btn-primary"
                disabled={isSwitching}
                onClick={() => switchChain({ chainId: targetNetwork.id })}
              >
                {isSwitching ? "Switching…" : "Switch to Base"}
              </button>
            </div>
          ) : (
            <>
              <div className="grid grid-cols-2 gap-4 text-sm mb-5">
                <Row label="$CLAWD balance" value={fmt(clawdBalance as bigint | undefined, 18, 2)} />
                <Row
                  label="$CLAWD price (USD, owner-set)"
                  value={
                    clawdUsdPrice !== undefined
                      ? `$${Number(formatUnits(clawdUsdPrice as bigint, 18)).toLocaleString(undefined, { maximumFractionDigits: 6 })}`
                      : "—"
                  }
                />
                <Row
                  label="Eligible free mints"
                  value={eligibleFreeMints !== undefined ? (eligibleFreeMints as bigint).toString() : "—"}
                />
                <Row
                  label="Free mints used"
                  value={usedFreeMints !== undefined ? (usedFreeMints as bigint).toString() : "—"}
                />
              </div>

              <div className="flex items-center gap-3 mb-5">
                <span className="text-sm text-base-content/70">Quantity</span>
                <div className="join">
                  <button
                    type="button"
                    className="btn btn-sm join-item"
                    onClick={() => setQuantity(q => Math.max(1, q - 1))}
                    disabled={quantity <= 1 || isMining}
                  >
                    −
                  </button>
                  <input
                    type="number"
                    className="input input-sm join-item w-20 text-center"
                    value={quantity}
                    min={1}
                    max={maxQty}
                    onChange={e => {
                      const n = Number(e.target.value);
                      if (Number.isFinite(n)) setQuantity(Math.min(maxQty, Math.max(1, Math.floor(n))));
                    }}
                  />
                  <button
                    type="button"
                    className="btn btn-sm join-item"
                    onClick={() => setQuantity(q => Math.min(maxQty, q + 1))}
                    disabled={quantity >= maxQty || isMining}
                  >
                    +
                  </button>
                </div>
                <span className="text-xs text-base-content/50">max {maxQty}</span>
              </div>

              <div className="bg-base-200 rounded-md p-4 text-sm mb-5 ap-card">
                <Row label={`Free (${freeQty.toString()})`} value={`0 ETH`} subtle />
                <Row
                  label={`Paid (${paidQty.toString()})`}
                  value={mintPrice !== undefined ? `${fmtEth((mintPrice as bigint) * paidQty)} ETH` : "—"}
                  subtle
                />
                <div className="ap-divider my-2" />
                <Row label="Total" value={`${fmtEth(totalCost)} ETH`} bold />
              </div>

              <button onClick={onMint} disabled={buttonDisabled} className="btn btn-primary w-full ap-pixel text-lg">
                {remainingSupply === 0n
                  ? "SOLD OUT"
                  : isMining
                    ? "Minting…"
                    : cooldownActive
                      ? "Confirming…"
                      : `Mint ${quantity} for ${fmtEth(totalCost)} ETH`}
              </button>

              <p className="text-xs text-base-content/50 mt-3 text-center m-0">
                Free mints are claimed first. Holding ≥ $50 of $CLAWD gets 1 free mint (max 1 per wallet, 2,000 global
                cap).
              </p>
            </>
          )}
        </section>
      </div>
    </div>
  );
};

export default Home;

const StatCard = ({ label, value }: { label: string; value: string }) => (
  <div className="ap-card rounded-box p-4 bg-base-100/60">
    <div className="ap-pixel text-xs tracking-widest text-base-content/60">{label}</div>
    <div className="ap-pixel text-2xl mt-1 ap-glow">{value}</div>
  </div>
);

const Row = ({ label, value, subtle, bold }: { label: string; value: string; subtle?: boolean; bold?: boolean }) => (
  <div className="flex justify-between items-baseline gap-2">
    <span className={`${subtle ? "text-base-content/60" : "text-base-content/80"} text-xs`}>{label}</span>
    <span className={`${bold ? "ap-pixel ap-glow text-lg" : "ap-pixel text-sm"}`}>{value}</span>
  </div>
);
