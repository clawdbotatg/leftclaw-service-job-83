"use client";

import React from "react";
import { Address } from "@scaffold-ui/components";
import { hardhat } from "viem/chains";
import { SwitchTheme } from "~~/components/SwitchTheme";
import { Faucet } from "~~/components/scaffold-eth";
import { useScaffoldContract } from "~~/hooks/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";

/**
 * Site footer for Ai Punks. SE2 branding (Fork-me / BuidlGuidl / Support /
 * native currency price badge) is intentionally removed for a clean
 * production deploy.
 */
export const Footer = () => {
  const { targetNetwork } = useTargetNetwork();
  const isLocalNetwork = targetNetwork.id === hardhat.id;
  const { data: aiPunks } = useScaffoldContract({ contractName: "AiPunks" });
  const contractAddress = aiPunks?.address;

  return (
    <div className="min-h-0 py-5 px-1 mb-11 lg:mb-0">
      <div>
        <div className="fixed flex justify-between items-center w-full z-10 p-4 bottom-0 left-0 pointer-events-none">
          <div className="flex flex-col md:flex-row gap-2 pointer-events-auto">{isLocalNetwork && <Faucet />}</div>
          <SwitchTheme className={`pointer-events-auto ${isLocalNetwork ? "self-end md:self-auto" : ""}`} />
        </div>
      </div>
      <div className="w-full">
        <div className="ap-divider w-full mb-3" />
        <div className="flex flex-col md:flex-row justify-center items-center gap-3 text-sm w-full px-4">
          <span className="ap-pixel ap-glow text-base">Ai Punks</span>
          {contractAddress && (
            <div className="flex items-center gap-2">
              <span className="text-base-content/60">contract</span>
              <Address address={contractAddress} chain={targetNetwork} />
            </div>
          )}
          <span className="hidden md:inline text-base-content/40">·</span>
          <a href="https://leftclaw.services" target="_blank" rel="noreferrer" className="link text-base-content/70">
            Built for LeftClaw Job #83
          </a>
        </div>
      </div>
    </div>
  );
};
