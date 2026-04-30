import { wagmiConnectors } from "./wagmiConnectors";
import { Chain, createClient, fallback, http } from "viem";
import { hardhat, mainnet } from "viem/chains";
import { createConfig } from "wagmi";
import scaffoldConfig, { DEFAULT_ALCHEMY_API_KEY, ScaffoldConfig } from "~~/scaffold.config";
import { getAlchemyHttpUrl } from "~~/utils/scaffold-eth";

const { targetNetworks } = scaffoldConfig;

// We always want to have mainnet enabled (ENS resolution, ETH price, etc). But only once.
export const enabledChains = targetNetworks.find((network: Chain) => network.id === 1)
  ? targetNetworks
  : ([...targetNetworks, mainnet] as const);

export const wagmiConfig = createConfig({
  chains: enabledChains,
  connectors: wagmiConnectors(),
  ssr: true,
  client: ({ chain }) => {
    // RPC fallback policy:
    // 1. explicit per-chain override (scaffoldConfig.rpcOverrides) — first
    // 2. Alchemy (if NEXT_PUBLIC_ALCHEMY_API_KEY is set, or scaffold's default key)
    // 3. Mainnet only: BuidlGuidl public RPC (for ENS / price reads)
    // We do NOT add a bare `http()` fallback for the target chain because viem would
    // silently route to the chain's public RPC, which is rate-limited and violates the
    // project RPC rule. Bare `http()` is only used as a last resort when no URL is configured.
    const rpcOverrideUrl = (scaffoldConfig.rpcOverrides as ScaffoldConfig["rpcOverrides"])?.[chain.id];
    const alchemyHttpUrl = getAlchemyHttpUrl(chain.id);
    const isUsingDefaultKey = scaffoldConfig.alchemyApiKey === DEFAULT_ALCHEMY_API_KEY;

    const rpcFallbacks: ReturnType<typeof http>[] = [];

    if (rpcOverrideUrl) rpcFallbacks.push(http(rpcOverrideUrl));
    if (alchemyHttpUrl && !isUsingDefaultKey) rpcFallbacks.push(http(alchemyHttpUrl));
    if (chain.id === mainnet.id) rpcFallbacks.push(http("https://mainnet.rpc.buidlguidl.com"));
    // When using the shared default Alchemy key, treat Alchemy as a backup behind the BG RPC.
    if (alchemyHttpUrl && isUsingDefaultKey) rpcFallbacks.push(http(alchemyHttpUrl));

    // Last-ditch only — no explicit URLs configured for this chain.
    if (rpcFallbacks.length === 0) rpcFallbacks.push(http());

    return createClient({
      chain,
      transport: fallback(rpcFallbacks),
      ...(chain.id !== (hardhat as Chain).id ? { pollingInterval: scaffoldConfig.pollingInterval } : {}),
    });
  },
});
