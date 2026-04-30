import type { Metadata } from "next";

// Production URL resolution priority:
//   1. NEXT_PUBLIC_PRODUCTION_URL (recommended — set to the live IPFS gateway URL at build time)
//   2. VERCEL_PROJECT_PRODUCTION_URL (auto-injected by Vercel)
//   3. fallback: dev server (yarn start runs `next start` on $PORT or 3000)
//
// For IPFS static exports we must never bake `http://localhost:3000` into prerendered HTML —
// that breaks every social unfurl. Stage 9 (or the operator) should set
// `NEXT_PUBLIC_PRODUCTION_URL=https://<CID>.ipfs.community.bgipfs.com` at build time.
// As a safe default for IPFS builds without that env var, we use a neutral placeholder so the
// rendered tags are at least non-localhost.
const explicitProductionUrl = process.env.NEXT_PUBLIC_PRODUCTION_URL
  ? process.env.NEXT_PUBLIC_PRODUCTION_URL.startsWith("http")
    ? process.env.NEXT_PUBLIC_PRODUCTION_URL
    : `https://${process.env.NEXT_PUBLIC_PRODUCTION_URL}`
  : process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : undefined;

const isIpfsBuild = process.env.NEXT_PUBLIC_IPFS_BUILD === "true";

// For IPFS builds without an explicit production URL, prefer a neutral placeholder
// over localhost. Social unfurls will fail gracefully instead of pointing at a dev server.
const ipfsPlaceholder = "https://aipunks.eth.link";

const baseUrl =
  explicitProductionUrl ?? (isIpfsBuild ? ipfsPlaceholder : `http://localhost:${process.env.PORT || 3000}`);

const titleTemplate = "%s | Ai Punks";

export const getMetadata = ({
  title,
  description,
  imageRelativePath = "/thumbnail.jpg",
}: {
  title: string;
  description: string;
  imageRelativePath?: string;
}): Metadata => {
  const imageUrl = `${baseUrl}${imageRelativePath}`;

  return {
    metadataBase: new URL(baseUrl),
    title: {
      default: title,
      template: titleTemplate,
    },
    description: description,
    openGraph: {
      title: {
        default: title,
        template: titleTemplate,
      },
      description: description,
      images: [
        {
          url: imageUrl,
        },
      ],
    },
    twitter: {
      title: {
        default: title,
        template: titleTemplate,
      },
      description: description,
      images: [imageUrl],
    },
    icons: {
      icon: [
        {
          url: "/favicon.png",
          sizes: "32x32",
          type: "image/png",
        },
      ],
    },
  };
};
