"use client";

import { useState } from "react";

// Mock price for Sepolia testnet.
// On mainnet, replace with Chainlink ETH/USD feed read via useReadContract.
const MOCK_ETH_USD = 3500;

export function useEthPrice(): { ethPrice: number; isLoading: boolean } {
  const [ethPrice] = useState(MOCK_ETH_USD);
  return { ethPrice, isLoading: false };
}

/** Format a WETH/ETH amount to its USD equivalent string. */
export function formatUsd(ethAmount: number, ethPrice: number): string {
  const usd = ethAmount * ethPrice;
  if (usd === 0) return "$0.00";
  if (usd > 0 && usd < 0.01) return "<$0.01";
  return `$${usd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
