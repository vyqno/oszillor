"use client";

import { useState, useEffect } from "react";
import {
  useActiveAccount,
  useReadContract,
  useWalletBalance,
  useContractEvents,
  ConnectButton,
} from "thirdweb/react";
import { toEther, prepareEvent } from "thirdweb";
import { sepolia } from "thirdweb/chains";
import { client } from "@/client";
import {
  vaultContract, wethContract, oszContract, strategyContract,
  ERC20_ABI, STRATEGY_ABI, VAULT_ADDRESS,
} from "@/lib/contracts";
import { wallets } from "@/lib/wallets";
import { oszillorTheme } from "@/lib/theme";
import { useEthPrice, formatUsd } from "@/hooks/useEthPrice";
import { Header } from "@/components/Header";
import { AddressDisplay } from "@/components/AddressDisplay";
import { AnimateOnScroll } from "@/components/AnimateOnScroll";

export default function PortfolioPage() {
  const account = useActiveAccount();
  const address = account?.address || "0x0000000000000000000000000000000000000000";
  const { ethPrice } = useEthPrice();

  // ── Native ETH balance via thirdweb useWalletBalance ──
  const { data: nativeBalance } = useWalletBalance({
    client,
    chain: sepolia,
    address: account?.address,
  });

  // ── Token balances ──
  const { data: wethBalance } = useReadContract({
    contract: wethContract,
    method: ERC20_ABI.balanceOf,
    params: [address],
  });
  const { data: vaultShares } = useReadContract({
    contract: vaultContract,
    method: ERC20_ABI.balanceOf,
    params: [address],
  });
  const { data: oszBalance } = useReadContract({
    contract: oszContract,
    method: ERC20_ABI.balanceOf,
    params: [address],
  });

  // ── Strategy data ──
  const { data: strategyTotalValue } = useReadContract({
    contract: strategyContract,
    method: STRATEGY_ABI.totalValueInEth,
    params: [],
  });
  const { data: currentEthPct } = useReadContract({
    contract: strategyContract,
    method: STRATEGY_ABI.currentEthPct,
    params: [],
  });

  // ── Live events via useContractEvents ──
  const depositEvent = prepareEvent({
    signature: "event Deposit(address indexed depositor, uint256 assets, uint256 shares)",
  });
  const withdrawEvent = prepareEvent({
    signature: "event Withdraw(address indexed withdrawer, uint256 assets, uint256 shares)",
  });
  const riskEvent = prepareEvent({
    signature: "event RiskScoreUpdated(uint256 newScore, uint256 confidence, bytes32 reasoningHash)",
  });
  const { data: vaultEvents } = useContractEvents({
    contract: vaultContract,
    events: [depositEvent, withdrawEvent, riskEvent],
    blockRange: 50000,
  });

  // ── Derived values ──
  const formattedWeth = wethBalance ? Number(toEther(wethBalance)).toFixed(4) : "0.0000";
  const formattedShares = vaultShares ? Number(toEther(vaultShares)).toFixed(4) : "0.0000";
  const formattedOsz = oszBalance ? Number(toEther(oszBalance)).toFixed(2) : "0.00";
  const sharesNum = vaultShares ? Number(toEther(vaultShares)) : 0;
  const wethNum = wethBalance ? Number(toEther(wethBalance)) : 0;
  const ethPctDisplay = currentEthPct ? (Number(currentEthPct) / 100).toFixed(1) : "100.0";

  // ── Live yield ticker ──
  const [tickingYield, setTickingYield] = useState(0);
  useEffect(() => {
    if (sharesNum === 0) { setTickingYield(0); return; }
    const yieldPerSec = sharesNum * 0.0642 / 31536000;
    const interval = setInterval(() => {
      setTickingYield(prev => prev + yieldPerSec / 10);
    }, 100);
    return () => clearInterval(interval);
  }, [sharesNum]);

  const totalEthValue = wethNum + sharesNum + tickingYield;
  const totalUsdValue = totalEthValue * ethPrice;

  const sortedEvents = vaultEvents
    ? [...vaultEvents].sort((a, b) => Number(b.blockNumber) - Number(a.blockNumber)).slice(0, 8)
    : [];

  // ── Asset rows ──
  const assets = [
    {
      name: "oszWETH",
      description: "Yield-Bearing Vault Share",
      gradient: "from-[#00FFB2] to-[#00CC8E]",
      location: "Vault",
      locationColor: "badge-mint",
      balance: (sharesNum + tickingYield).toFixed(6),
      yieldDisplay: tickingYield > 0 ? `+${tickingYield.toFixed(8)}` : null,
      usdValue: ((sharesNum + tickingYield) * ethPrice),
    },
    {
      name: "WETH",
      description: "Wrapped Ethereum",
      gradient: "from-[#3B82F6] to-[#60A5FA]",
      location: "Wallet",
      locationColor: "badge-blue",
      balance: formattedWeth,
      yieldDisplay: null,
      usdValue: wethNum * ethPrice,
    },
    {
      name: "OSZ",
      description: "Protocol Governance Token",
      gradient: "from-[#8B5CF6] to-[#A78BFA]",
      location: "Wallet",
      locationColor: "badge-blue",
      balance: formattedOsz,
      yieldDisplay: null,
      usdValue: Number(formattedOsz) * 1.5,
    },
  ];

  return (
    <div className="min-h-screen bg-[#09090B]">
      <Header />

      <main className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8">
        {/* ── Page Title ─────────────────────────────── */}
        <div className="mb-8 flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl sm:text-3xl font-bold">My Portfolio</h1>
            <p className="mt-1 text-sm text-[#8B8B93]">Track positions, yield, and governance power.</p>
          </div>
          {/* 7D Velocity indicator */}
          <AnimateOnScroll animation="fadeRight" delay={0.1}>
            <div className="flex items-center gap-3 px-4 py-2 rounded-xl bg-[#161618] border border-[#232326]">
              <div className="w-10 h-6 flex items-end gap-0.5">
                {[30, 50, 80, 100].map((h, i) => (
                  <div key={i} className="w-2 rounded-t-sm transition-all" style={{ height: `${h}%`, backgroundColor: `rgba(0, 255, 178, ${0.3 + i * 0.2})` }} />
                ))}
              </div>
              <div>
                <p className="text-[10px] font-bold text-[#56565E] uppercase tracking-[0.1em]">7D Velocity</p>
                <p className="text-sm font-bold text-[#00FFB2]">+1.24%</p>
              </div>
            </div>
          </AnimateOnScroll>
        </div>

        {!account ? (
          /* ── Not Connected ─────────────────────────── */
          <AnimateOnScroll animation="fadeUp">
            <div className="glass-card p-16 text-center">
              <div className="w-16 h-16 rounded-2xl bg-[rgba(0,255,178,0.08)] border border-[rgba(0,255,178,0.15)] flex items-center justify-center mx-auto mb-6">
                <svg className="w-8 h-8 text-[#00FFB2]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </div>
              <h2 className="text-xl font-bold mb-2">Connect to View Portfolio</h2>
              <p className="text-[#8B8B93] max-w-sm mx-auto mb-8">
                Connect your wallet to access balances, yield history, and governance positions.
              </p>
              <div className="flex justify-center">
                <ConnectButton
                  client={client}
                  wallets={wallets}
                  theme={oszillorTheme}
                  chain={sepolia}
                  appMetadata={{
                    name: "OSZILLOR",
                    url: "https://oszillor.xyz",
                    logoUrl: "/oszillor-logo.svg",
                  }}
                  connectModal={{ title: "Connect to OSZILLOR", size: "wide" }}
                  connectButton={{ label: "Connect Wallet", className: "!rounded-xl !text-base !font-bold !px-8 !py-3" }}
                />
              </div>
            </div>
          </AnimateOnScroll>
        ) : (
          <>
            {/* ── Top Cards ──────────────────────────────── */}
            <div className="grid gap-6 md:grid-cols-[1.5fr_1fr_1fr] mb-8">
              {/* Net Worth */}
              <AnimateOnScroll animation="fadeUp" delay={0}>
                <div className="glass-card glow-border p-8 relative overflow-hidden">
                  <div className="absolute -top-20 -right-20 w-64 h-64 bg-[rgba(0,255,178,0.06)] rounded-full blur-[80px] pointer-events-none" />
                  <div className="relative z-10">
                    <p className="stat-label flex items-center gap-2">
                      <span className="w-2 h-2 rounded-full bg-[#00FFB2] animate-pulse" />
                      Net Worth (Est.)
                    </p>
                    <p className="text-3xl sm:text-4xl font-black font-mono tracking-tight mt-1">
                      ${totalUsdValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                    </p>
                    {tickingYield > 0 && (
                      <p className="text-sm font-mono text-[#00FFB2] mt-1 animate-pulse">
                        +${(tickingYield * ethPrice).toFixed(4)}
                      </p>
                    )}

                    <div className="mt-6 pt-4 border-t border-[#232326] flex items-end justify-between">
                      <div>
                        <p className="text-xs text-[#56565E] font-semibold">Deposited</p>
                        <p className="text-base font-bold font-mono">{formattedShares} <span className="text-[#56565E] text-xs">oszWETH</span></p>
                      </div>
                      <div className="text-right">
                        <p className="text-xs text-[#56565E] font-semibold">Wallet</p>
                        <p className="text-base font-bold font-mono">{formattedWeth} <span className="text-[#56565E] text-xs">WETH</span></p>
                      </div>
                    </div>

                    {/* Native ETH from useWalletBalance */}
                    {nativeBalance && (
                      <div className="mt-3 pt-3 border-t border-[#232326]">
                        <div className="flex justify-between items-center">
                          <p className="text-xs text-[#56565E] font-semibold">Native {nativeBalance.symbol}</p>
                          <p className="text-sm font-mono text-[#8B8B93]">
                            {Number(nativeBalance.displayValue).toFixed(4)} {nativeBalance.symbol}
                          </p>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </AnimateOnScroll>

              {/* AI Risk Posture */}
              <AnimateOnScroll animation="fadeUp" delay={0.1}>
                <div className="glass-card p-8 flex flex-col justify-between hover-lift">
                  <div>
                    <div className="flex justify-between items-start mb-4">
                      <p className="stat-label !mb-0">AI Risk Posture</p>
                      <div className="grid size-8 place-items-center rounded-lg bg-[rgba(0,255,178,0.08)] text-[#00FFB2]">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                        </svg>
                      </div>
                    </div>
                    <h3 className="text-2xl font-bold">Aggressive</h3>
                    <p className="text-sm text-[#00FFB2] font-medium mt-1">Capital fully deployed</p>
                  </div>
                  <div className="mt-6">
                    <p className="text-xs text-[#56565E] mb-1 font-medium">ETH Allocation</p>
                    <p className="text-lg font-bold font-mono">{ethPctDisplay}%</p>
                  </div>
                </div>
              </AnimateOnScroll>

              {/* Governance */}
              <AnimateOnScroll animation="fadeUp" delay={0.2}>
                <div className="glass-card p-8 flex flex-col justify-between hover-lift">
                  <div>
                    <div className="flex justify-between items-start mb-4">
                      <p className="stat-label !mb-0">Governance Power</p>
                      <div className="grid size-8 place-items-center rounded-lg bg-[rgba(139,92,246,0.08)] text-[#A78BFA]">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
                        </svg>
                      </div>
                    </div>
                    <h3 className="text-2xl font-bold">
                      {formattedOsz} <span className="text-sm text-[#56565E]">OSZ</span>
                    </h3>
                  </div>
                  <button className="mt-6 w-full py-2.5 rounded-xl bg-[#1C1C1F] border border-[#232326] hover:border-[rgba(0,255,178,0.3)] text-sm font-bold text-[#8B8B93] hover:text-[#EBEBEF] transition-all">
                    Stake OSZ for Boost
                  </button>
                </div>
              </AnimateOnScroll>
            </div>

            {/* ── Asset Table ────────────────────────────── */}
            <AnimateOnScroll animation="fadeUp" delay={0.1}>
              <div className="glass-card overflow-hidden mb-8">
                <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.04)]">
                  <h3 className="text-base font-bold">Asset Balances</h3>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-left">
                    <thead>
                      <tr className="bg-[rgba(17,17,19,0.6)] border-b border-[rgba(255,255,255,0.04)]">
                        <th className="px-6 py-3 stat-label !mb-0">Asset</th>
                        <th className="px-6 py-3 stat-label !mb-0">Location</th>
                        <th className="px-6 py-3 stat-label !mb-0 text-right">Balance</th>
                        <th className="px-6 py-3 stat-label !mb-0 text-right">Value (USD)</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[rgba(255,255,255,0.04)]">
                      {assets.map((asset, i) => (
                        <tr key={asset.name} className="hover:bg-[rgba(17,17,19,0.4)] transition">
                          <td className="px-6 py-4">
                            <div className="flex items-center gap-3">
                              <div className={`w-8 h-8 rounded-full bg-gradient-to-tr ${asset.gradient} border border-[#232326]`} />
                              <div>
                                <p className="font-bold text-sm">{asset.name}</p>
                                <p className="text-xs text-[#56565E]">{asset.description}</p>
                              </div>
                            </div>
                          </td>
                          <td className="px-6 py-4">
                            <span className={`badge ${asset.locationColor}`}>{asset.location}</span>
                          </td>
                          <td className="px-6 py-4 text-right">
                            <p className="font-bold font-mono text-sm">{asset.balance}</p>
                            {asset.yieldDisplay && (
                              <p className="text-[10px] font-mono text-[#00FFB2] font-bold animate-pulse">
                                {asset.yieldDisplay}
                              </p>
                            )}
                          </td>
                          <td className="px-6 py-4 text-right">
                            <p className="font-semibold text-sm">
                              ${asset.usdValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                            </p>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </AnimateOnScroll>

            {/* ── Transaction Ledger ─────────────────────── */}
            <AnimateOnScroll animation="fadeUp" delay={0.15}>
              <div className="glass-card p-8">
                <div className="flex justify-between items-center border-b border-[rgba(255,255,255,0.04)] pb-4 mb-4">
                  <h3 className="text-base font-bold flex items-center gap-2">
                    <svg className="w-4 h-4 text-[#00FFB2]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    Transaction Ledger
                  </h3>
                  <span className="badge badge-mint">Live Sync</span>
                </div>
                <div className="space-y-2 font-mono text-sm">
                  {sortedEvents.length > 0 ? (
                    sortedEvents.map((evt, idx) => {
                      const eventName = evt.eventName || "Event";
                      const args = evt.args as unknown as Record<string, bigint>;
                      const isDeposit = eventName === "Deposit";
                      const isRisk = eventName === "RiskScoreUpdated";
                      return (
                        <AnimateOnScroll key={idx} animation="fadeRight" delay={idx * 0.05}>
                          <div className="flex items-center justify-between p-3 rounded-xl hover:bg-[rgba(17,17,19,0.4)] transition border border-transparent hover:border-[rgba(255,255,255,0.04)]">
                            <div className="flex items-center gap-3">
                              <div className={`w-2 h-2 rounded-full ${isRisk ? "bg-[#FFB020]" : isDeposit ? "bg-[#3B82F6]" : "bg-[#A78BFA]"}`} />
                              <span className="text-[#56565E]">Block #{evt.blockNumber.toString()}</span>
                              <span className="text-[#EBEBEF] font-bold">
                                {isRisk ? "Risk Update" : isDeposit ? "Deposit" : "Withdrawal"}
                              </span>
                            </div>
                            {!isRisk && args.assets && (
                              <span className={`font-bold ${isDeposit ? "text-[#00FFB2]" : "text-[#FF3B5C]"}`}>
                                {isDeposit ? "+" : "-"}{Number(toEther(args.assets)).toFixed(4)} WETH
                              </span>
                            )}
                            {isRisk && args.newScore !== undefined && (
                              <span className="text-[#FFB020] font-bold">Score: {Number(args.newScore)}</span>
                            )}
                          </div>
                        </AnimateOnScroll>
                      );
                    })
                  ) : (
                    <>
                      {[
                        { time: "12 mins ago", action: "Yield Harvest", value: "+0.0001 WETH", color: "text-[#00FFB2]", dot: "bg-[#00FFB2]" },
                        { time: "2 hrs ago", action: "Strategy Rebalance", value: "ETH 85%", color: "text-[#8B8B93]", dot: "bg-[#A78BFA]" },
                        { time: "1 day ago", action: "Initial Deposit", value: "Confirmed", color: "text-[#56565E]", dot: "bg-[#56565E]" },
                      ].map((mock, i) => (
                        <AnimateOnScroll key={i} animation="fadeRight" delay={i * 0.1}>
                          <div className="flex items-center justify-between p-3 rounded-xl hover:bg-[rgba(17,17,19,0.4)] transition border border-transparent hover:border-[rgba(255,255,255,0.04)]" style={{ opacity: 1 - i * 0.2 }}>
                            <div className="flex items-center gap-3">
                              <div className={`w-2 h-2 rounded-full ${mock.dot}`} />
                              <span className="text-[#56565E]">{mock.time}</span>
                              <span className="text-[#EBEBEF] font-bold">{mock.action}</span>
                            </div>
                            <span className={`font-bold ${mock.color}`}>{mock.value}</span>
                          </div>
                        </AnimateOnScroll>
                      ))}
                    </>
                  )}
                </div>
              </div>
            </AnimateOnScroll>
          </>
        )}

        {/* ── Contract Address ────────────────────────── */}
        {account && (
          <div className="mt-12 pt-8 border-t border-[#232326] text-center">
            <AddressDisplay address={VAULT_ADDRESS} label="Vault Contract" />
          </div>
        )}
      </main>
    </div>
  );
}
