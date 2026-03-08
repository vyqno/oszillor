"use client";

import { useState } from "react";

interface AddressDisplayProps {
  address: string;
  label?: string;
}

/** Truncated address with copy-to-clipboard and Etherscan link. */
export function AddressDisplay({ address, label }: AddressDisplayProps) {
  const [copied, setCopied] = useState(false);

  if (!address || address === "0x0000000000000000000000000000000000000000") return null;

  const truncated = `${address.slice(0, 6)}...${address.slice(-4)}`;
  const explorerUrl = `https://sepolia.etherscan.io/address/${address}`;

  const handleCopy = async () => {
    await navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <span className="inline-flex items-center gap-1.5">
      {label && <span className="text-xs text-[#56565E]">{label}</span>}
      <a
        href={explorerUrl}
        target="_blank"
        rel="noopener noreferrer"
        className="font-mono text-xs text-[#8B8B93] hover:text-[#00FFB2] transition underline decoration-dotted underline-offset-2"
        title={address}
      >
        {truncated}
      </a>
      <button
        onClick={handleCopy}
        className="text-[#56565E] hover:text-[#8B8B93] transition cursor-pointer"
        title={copied ? "Copied!" : "Copy address"}
      >
        {copied ? (
          <svg className="w-3 h-3 text-[#00FFB2]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        ) : (
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
          </svg>
        )}
      </button>
    </span>
  );
}
