"use client";

import { useState, useEffect } from "react";
import {
  useActiveAccount,
  useReadContract,
  useWalletBalance,
  useActiveWalletChain,
  useSwitchActiveWalletChain,
  ConnectButton,
  TransactionButton,
  PayEmbed,
  useContractEvents,
} from "thirdweb/react";
import { prepareContractCall, toWei, toEther, prepareEvent } from "thirdweb";
import { sepolia } from "thirdweb/chains";
import { client } from "@/client";
import {
  vaultContract, wethContract, strategyContract,
  VAULT_ABI, ERC20_ABI, STRATEGY_ABI,
  VAULT_ADDRESS, WETH_ADDRESS, STRATEGY_ADDRESS,
} from "@/lib/contracts";
import { wallets } from "@/lib/wallets";
import { oszillorTheme } from "@/lib/theme";
import { parseContractError } from "@/lib/errors";
import { useEthPrice, formatUsd } from "@/hooks/useEthPrice";
import { Header } from "@/components/Header";
import { AddressDisplay } from "@/components/AddressDisplay";
import { AnimateOnScroll } from "@/components/AnimateOnScroll";
import confetti from "canvas-confetti";

const RISK_LABELS = ["SAFE", "CAUTION", "DANGER", "CRITICAL"] as const;
const RISK_COLORS: Record<string, string> = {
  SAFE: "#00FFB2",
  CAUTION: "#FFB020",
  DANGER: "#FF6B35",
  CRITICAL: "#FF3B5C",
};

export default function DashboardPage() {
  const account = useActiveAccount();
  const chain = useActiveWalletChain();
  const switchChain = useSwitchActiveWalletChain();
  const wrongChain = account && chain && chain.id !== sepolia.id;

  const { ethPrice } = useEthPrice();
  const [activeTab, setActiveTab] = useState<"deposit" | "withdraw">("deposit");
  const [amount, setAmount] = useState("");
  const [isPanicking, setIsPanicking] = useState(false);
  const [showPayEmbed, setShowPayEmbed] = useState(false);
  const [txError, setTxError] = useState<string | null>(null);
  const [tickingYield, setTickingYield] = useState(0);
  const [mockLogs, setMockLogs] = useState<string[]>([]);
  const [isSwitching, setIsSwitching] = useState(false);

  // ── Native ETH balance via thirdweb useWalletBalance ──
  const { data: nativeBalance } = useWalletBalance({
    client,
    chain: sepolia,
    address: account?.address,
  });

  // ── WETH balance via thirdweb useWalletBalance (token mode) ──
  const { data: wethTokenBalance } = useWalletBalance({
    client,
    chain: sepolia,
    address: account?.address,
    tokenAddress: WETH_ADDRESS,
  });

  // ── Vault contract reads ──
  const { data: totalAssets } = useReadContract({
    contract: vaultContract,
    method: VAULT_ABI.totalAssets,
    params: [],
  });
  const { data: isPaused } = useReadContract({
    contract: vaultContract,
    method: VAULT_ABI.paused,
    params: [],
  });
  const { data: emergencyModeActive } = useReadContract({
    contract: vaultContract,
    method: VAULT_ABI.emergencyMode,
    params: [],
  });
  const { data: riskScore } = useReadContract({
    contract: vaultContract,
    method: VAULT_ABI.currentRiskScore,
    params: [],
  });
  const { data: riskLevel } = useReadContract({
    contract: vaultContract,
    method: VAULT_ABI.riskLevel,
    params: [],
  });
  const { data: allowance } = useReadContract({
    contract: wethContract,
    method: ERC20_ABI.allowance,
    params: [account?.address || "0x0000000000000000000000000000000000000000", VAULT_ADDRESS],
  });
  const { data: wethBalance } = useReadContract({
    contract: wethContract,
    method: ERC20_ABI.balanceOf,
    params: [account?.address || "0x0000000000000000000000000000000000000000"],
  });
  const { data: vaultShares } = useReadContract({
    contract: vaultContract,
    method: ERC20_ABI.balanceOf,
    params: [account?.address || "0x0000000000000000000000000000000000000000"],
  });
  const { data: vaultWethBalance } = useReadContract({
    contract: wethContract,
    method: ERC20_ABI.balanceOf,
    params: [VAULT_ADDRESS],
  });

  // ── Strategy reads ──
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
  const { data: recentDeposits } = useContractEvents({
    contract: vaultContract,
    events: [depositEvent, withdrawEvent],
    blockRange: 50000,
  });

  // ── Derived values ──
  const amountWei = amount && !isNaN(Number(amount)) ? toWei(amount) : BigInt(0);
  const needsApproval = allowance !== undefined && allowance < amountWei && activeTab === "deposit";
  const tvl = totalAssets ? Number(toEther(totalAssets)).toFixed(4) : "0.0000";
  const formattedWethBalance = wethBalance ? Number(toEther(wethBalance)).toFixed(4) : "0.0000";
  const formattedVaultShares = vaultShares ? Number(toEther(vaultShares)).toFixed(4) : "0.0000";
  const vaultSharesNum = vaultShares ? Number(toEther(vaultShares)) : 0;
  const riskLabel = riskLevel !== undefined ? RISK_LABELS[Number(riskLevel)] || "UNKNOWN" : "SYNCING";
  const riskColor = RISK_COLORS[riskLabel] || "#8B8B93";
  const effectiveIsPaused = isPaused || emergencyModeActive || isPanicking;
  const ethPctDisplay = currentEthPct ? (Number(currentEthPct) / 100).toFixed(1) : "100.0";

  // ── Live yield ticker ──
  useEffect(() => {
    if (vaultSharesNum === 0) { setTickingYield(0); return; }
    const yieldPerSec = vaultSharesNum * 0.0642 / 31536000;
    const interval = setInterval(() => {
      setTickingYield(prev => prev + yieldPerSec / 10);
    }, 100);
    return () => clearInterval(interval);
  }, [vaultSharesNum]);

  // ── Panic simulation logs ──
  useEffect(() => {
    if (!isPanicking) { setMockLogs([]); return; }
    const logs = [
      "> [Oszillor AI] Ingesting real-time HTTP streams...",
      "> [Oszillor AI] Scanning DefiLlama reserve ratios...",
      "> ------------------------------------------------",
      "> [Oszillor AI] Sentiment Analysis :: FATAL PANIC",
      "> [Oszillor AI] Exploit Probability :: 98.4%",
      "> [Oszillor AI] Risk Vector :: Lido ETH Depeg",
      "> ------------------------------------------------",
      "> [Oszillor AI] DIRECTIVE: EMIT_PAUSE_AND_WITHDRAW",
      "> [SYSTEM] Vault Paused. Funds routing to safety.",
    ];
    let i = 0;
    setMockLogs(["> [SYSTEM] Initializing Risk Scanner..."]);
    const interval = setInterval(() => {
      if (i < logs.length) { setMockLogs(prev => [...prev, logs[i]]); i++; }
      else clearInterval(interval);
    }, 1200);
    return () => clearInterval(interval);
  }, [isPanicking]);

  // Clear errors on input change
  useEffect(() => { setTxError(null); }, [amount, activeTab]);

  const sortedEvents = recentDeposits
    ? [...recentDeposits].sort((a, b) => Number(b.blockNumber) - Number(a.blockNumber)).slice(0, 5)
    : [];

  return (
    <div className="min-h-screen bg-[#09090B]">
      <Header />

      <main className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8">
        {/* ── Page Title ─────────────────────────────── */}
        <div className="mb-8 flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl sm:text-3xl font-bold">Vault Dashboard</h1>
            <p className="mt-1 text-sm text-[#8B8B93]">Manage deposits and monitor strategy yield.</p>
          </div>
          {account && (
            <div className="flex items-center gap-3">
              <button
                onClick={() => setIsPanicking(!isPanicking)}
                className={`badge ${isPanicking ? "badge-danger" : "bg-[#1C1C1F] text-[#8B8B93] border border-[#232326]"} cursor-pointer hover:opacity-80 transition text-xs`}
              >
                <div className={`w-2 h-2 rounded-full ${isPanicking ? "bg-[#FF3B5C] animate-pulse" : "bg-[#FF3B5C]"}`} />
                {isPanicking ? "RESET" : "SIMULATE PANIC"}
              </button>
            </div>
          )}
        </div>

        {/* ── Stats Grid ─────────────────────────────── */}
        <div className="grid gap-6 md:grid-cols-4 mb-8">
          {/* TVL */}
          <AnimateOnScroll animation="fadeUp" delay={0}>
            <div className="glass-card p-8 hover-lift">
              <p className="stat-label">Protocol TVL</p>
              <p className="stat-value text-3xl">{tvl}</p>
              <p className="text-xs text-[#8B8B93] font-mono mt-2">
                WETH <span className="text-[#56565E]">({formatUsd(Number(tvl), ethPrice)})</span>
              </p>
            </div>
          </AnimateOnScroll>

          {/* Target APY */}
          <AnimateOnScroll animation="fadeUp" delay={0.05}>
            <div className="glass-card p-8 hover-lift">
              <p className="stat-label">Target Yield</p>
              <p className="stat-value text-3xl">6.42<span className="text-xl text-[#56565E]">%</span></p>
              {tickingYield > 0 && (
                <p className="text-xs font-mono text-[#00FFB2] mt-2 animate-pulse">
                  +{tickingYield.toFixed(8)} WETH <span className="text-[#56565E]">({formatUsd(tickingYield, ethPrice)})</span>
                </p>
              )}
            </div>
          </AnimateOnScroll>

          {/* Risk */}
          <AnimateOnScroll animation="fadeUp" delay={0.1}>
            <div className="glass-card p-8 hover-lift">
              <p className="stat-label">Risk Gatekeeper</p>
              <div className="flex items-center gap-2 mt-1">
                <div className="pulse-ring w-2.5 h-2.5 rounded-full" style={{ backgroundColor: riskColor, color: riskColor }} />
                <span className="stat-value text-2xl" style={{ color: effectiveIsPaused ? "#FF3B5C" : riskColor }}>
                  {effectiveIsPaused ? "PAUSED" : riskLabel}
                </span>
              </div>
              {riskScore !== undefined && (
                <div className="mt-3">
                  <div className="w-full h-1.5 rounded-full bg-[#1C1C1F] overflow-hidden">
                    <div
                      className="h-full rounded-full transition-all duration-500"
                      style={{
                        width: `${Math.min(Number(riskScore), 100)}%`,
                        backgroundColor: riskColor,
                      }}
                    />
                  </div>
                  <p className="text-[10px] font-mono text-[#56565E] mt-1">Score: {Number(riskScore)}/100</p>
                </div>
              )}
            </div>
          </AnimateOnScroll>

          {/* Native ETH Balance */}
          <AnimateOnScroll animation="fadeUp" delay={0.15}>
            <div className="glass-card p-8 hover-lift">
              <p className="stat-label">Wallet Balance</p>
              <p className="stat-value text-2xl">
                {nativeBalance ? Number(nativeBalance.displayValue).toFixed(4) : "-.--"}
              </p>
              <p className="text-xs text-[#56565E] font-mono mt-1">
                {nativeBalance?.symbol || "ETH"} (native){" "}
                {nativeBalance && <span className="text-[#8B8B93]">({formatUsd(Number(nativeBalance.displayValue), ethPrice)})</span>}
              </p>
              {wethTokenBalance && Number(wethTokenBalance.displayValue) > 0 && (
                <p className="text-xs font-mono text-[#8B8B93] mt-1">
                  + {Number(wethTokenBalance.displayValue).toFixed(4)} WETH{" "}
                  <span className="text-[#56565E]">({formatUsd(Number(wethTokenBalance.displayValue), ethPrice)})</span>
                </p>
              )}
            </div>
          </AnimateOnScroll>
        </div>

        {/* ── Main Grid ──────────────────────────────── */}
        <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr]">

          {/* ── Interaction Panel ──────────────────────── */}
          <AnimateOnScroll animation="fadeUp" delay={0.1}>
            <section className="glass-card p-8">
              {/* Tabs */}
              <div className="flex items-center gap-6 border-b border-[#232326] pb-5 mb-8">
                {(["deposit", "withdraw"] as const).map((tab) => (
                  <button
                    key={tab}
                    onClick={() => setActiveTab(tab)}
                    className={`text-sm font-bold uppercase tracking-[0.1em] pb-5 -mb-[21px] border-b-2 transition-all ${
                      activeTab === tab
                        ? "text-[#00FFB2] border-[#00FFB2]"
                        : "text-[#56565E] border-transparent hover:text-[#8B8B93]"
                    }`}
                  >
                    {tab}
                  </button>
                ))}
              </div>

              <h2 className="text-xl font-bold mb-2">
                {activeTab === "deposit" ? "Route Liquidity" : "Reclaim Liquidity"}
              </h2>
              <p className="text-sm text-[#8B8B93] mb-6 max-w-md">
                {activeTab === "deposit"
                  ? "Deposit WETH into the autonomous strategy. Yield generation begins instantly."
                  : "Withdraw your underlying WETH and accrued yield from the OSZILLOR strategy."}
              </p>

              {/* Input */}
              <div className="bg-[#111113] border border-[#232326] rounded-xl p-4 mb-6 input-glow transition-all">
                <div className="flex items-center justify-between mb-2">
                  <p className="stat-label !mb-0">Amount</p>
                  <p className="text-xs text-[#56565E] font-medium">
                    Balance:{" "}
                    <span className="text-[#8B8B93] font-bold font-mono">
                      {account ? (activeTab === "deposit" ? formattedWethBalance : formattedVaultShares) : "-.--"}
                    </span>{" "}
                    {activeTab === "deposit" ? "WETH" : "oszWETH"}
                  </p>
                </div>
                <div className="flex items-center gap-3">
                  <input
                    type="number"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value.replace(/-/g, ""))}
                    onKeyDown={(e) => { if (e.key === "-" || e.key === "e" || e.key === "E") e.preventDefault(); }}
                    placeholder="0.00"
                    className="w-full bg-transparent text-3xl sm:text-4xl font-extrabold text-[#EBEBEF] placeholder:text-[#2E2E32] focus:outline-none font-mono"
                    min="0"
                    step="0.01"
                  />
                  <div className="flex items-center gap-2 shrink-0">
                    <button
                      onClick={() => {
                        if (!account) return;
                        if (activeTab === "deposit" && wethBalance) setAmount(toEther(wethBalance));
                        else if (activeTab === "withdraw" && vaultShares) setAmount(toEther(vaultShares));
                      }}
                      className="px-3 py-1.5 rounded-lg bg-[rgba(0,255,178,0.08)] border border-[rgba(0,255,178,0.15)] text-[#00FFB2] text-xs font-bold hover:bg-[rgba(0,255,178,0.15)] transition"
                    >
                      MAX
                    </button>
                    <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[#1C1C1F] border border-[#232326]">
                      <div className={`w-4 h-4 rounded-full ${activeTab === "deposit" ? "bg-gradient-to-tr from-[#3B82F6] to-[#60A5FA]" : "bg-gradient-to-tr from-[#00FFB2] to-[#00CC8E]"}`} />
                      <span className="text-sm font-bold text-[#EBEBEF]">{activeTab === "deposit" ? "WETH" : "oszWETH"}</span>
                    </div>
                  </div>
                </div>

                {/* USD preview for input */}
                {amount && Number(amount) > 0 && (
                  <p className="mt-2 text-xs font-mono text-[#56565E] pl-1">
                    &asymp; {formatUsd(Number(amount), ethPrice)} USD
                  </p>
                )}

                {/* Test WETH faucet */}
                {account && activeTab === "deposit" && Number(formattedWethBalance) < 0.05 && (
                  <div className="mt-3 pt-3 border-t border-[#232326]">
                    <TransactionButton
                      transaction={() => prepareContractCall({ contract: wethContract, method: ERC20_ABI.mint, params: [account.address, toWei("0.05")] })}
                      onError={(e) => setTxError(parseContractError(e))}
                      theme={oszillorTheme}
                      className="!bg-transparent !p-0 !min-w-0 !h-auto !text-[#00FFB2] hover:!text-[#00CC8E] !text-xs !font-bold !shadow-none"
                    >
                      Claim 0.05 Test WETH
                    </TransactionButton>
                  </div>
                )}
              </div>

              {/* Action Buttons — 4-state flow: Connect → Network → Approve → Action */}
              {!account ? (
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
                    connectButton={{ label: "Connect Wallet to Continue", className: "!w-full !rounded-xl !text-base !font-bold !py-4" }}
                  />
                </div>
              ) : wrongChain ? (
                <button
                  onClick={async () => {
                    setIsSwitching(true);
                    try { await switchChain(sepolia); }
                    finally { setIsSwitching(false); }
                  }}
                  disabled={isSwitching}
                  className="btn-mint w-full"
                >
                  {isSwitching ? "Switching..." : "Switch to Sepolia"}
                </button>
              ) : needsApproval ? (
                <TransactionButton
                  transaction={() => prepareContractCall({
                    contract: wethContract,
                    method: ERC20_ABI.approve,
                    params: [VAULT_ADDRESS, amountWei],
                  })}
                  onError={(e) => setTxError(parseContractError(e))}
                  theme={oszillorTheme}
                  className="!w-full !rounded-xl !bg-[#00FFB2] hover:!bg-[#00CC8E] !text-[#09090B] !font-bold !text-base !py-4 !shadow-[0_0_20px_rgba(0,255,178,0.15)] transition-all"
                >
                  Approve WETH
                </TransactionButton>
              ) : (
                <TransactionButton
                  transaction={() => {
                    if (activeTab === "deposit") {
                      return prepareContractCall({ contract: vaultContract, method: VAULT_ABI.deposit, params: [amountWei, account.address] });
                    } else {
                      return prepareContractCall({ contract: vaultContract, method: VAULT_ABI.withdraw, params: [amountWei, account.address, account.address] });
                    }
                  }}
                  onTransactionConfirmed={() => {
                    confetti({
                      particleCount: 120,
                      spread: 80,
                      origin: { y: 0.6 },
                      colors: ["#00FFB2", "#00CC8E", "#3B82F6", "#EBEBEF"],
                    });
                    setAmount("");
                    setTxError(null);
                  }}
                  onError={(e) => setTxError(parseContractError(e))}
                  disabled={
                    effectiveIsPaused ||
                    !amount ||
                    amountWei === BigInt(0) ||
                    (activeTab === "deposit" && wethBalance !== undefined && amountWei > wethBalance) ||
                    (activeTab === "withdraw" && vaultShares !== undefined && amountWei > vaultShares)
                  }
                  theme={oszillorTheme}
                  className="!w-full !rounded-xl !bg-[#00FFB2] hover:!bg-[#00CC8E] !text-[#09090B] !font-bold !text-base !py-4 !shadow-[0_0_20px_rgba(0,255,178,0.15)] transition-all disabled:!opacity-30 disabled:!cursor-not-allowed disabled:!shadow-none"
                >
                  {activeTab === "deposit" ? "Execute Deposit" : "Execute Withdrawal"}
                </TransactionButton>
              )}

              {/* Inline error display */}
              {txError && (
                <div className="mt-3 flex items-start gap-2 p-3 rounded-xl bg-[rgba(255,59,92,0.08)] border border-[rgba(255,59,92,0.15)]">
                  <svg className="w-4 h-4 text-[#FF3B5C] shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                  <p className="text-sm text-[#FF3B5C] font-medium">{txError}</p>
                </div>
              )}

              {/* Insufficient balance warnings */}
              {amount && amountWei > BigInt(0) && activeTab === "deposit" && wethBalance !== undefined && amountWei > wethBalance && (
                <p className="mt-3 text-sm text-[#FF3B5C] font-bold text-center">Insufficient WETH balance.</p>
              )}
              {amount && amountWei > BigInt(0) && activeTab === "withdraw" && vaultShares !== undefined && amountWei > vaultShares && (
                <p className="mt-3 text-sm text-[#FF3B5C] font-bold text-center">Insufficient oszWETH balance.</p>
              )}

              {/* Emergency warning */}
              {effectiveIsPaused && (
                <div className="mt-4 flex items-start gap-2 p-4 rounded-xl bg-[rgba(255,59,92,0.06)] border border-[rgba(255,59,92,0.12)]">
                  <svg className="w-5 h-5 text-[#FF3B5C] shrink-0 animate-pulse" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                  <p className="text-sm text-[#FF3B5C] font-medium">
                    Vault is safeguarded. Operations are halted until the AI Gatekeeper resolves the anomaly.
                  </p>
                </div>
              )}
            </section>
          </AnimateOnScroll>

          {/* ── Right Panel: Strategy + Yield ──────────── */}
          <div className="space-y-6">
            {/* Live Position */}
            <AnimateOnScroll animation="fadeUp" delay={0.15}>
              <div className="glass-card p-8">
                <p className="stat-label mb-4">Your Live Position</p>
                <div className="bg-[#111113] border border-[#232326] rounded-xl p-4 mb-4">
                  <div className="flex justify-between items-center">
                    <div>
                      <p className="text-[10px] font-bold uppercase tracking-[0.1em] text-[#56565E] mb-1">Unrealized Yield</p>
                      <p className="font-mono text-[#00FFB2] font-extrabold text-lg">
                        +{tickingYield.toFixed(8)} <span className="text-xs">WETH</span>
                      </p>
                      <p className="text-[10px] font-mono text-[#56565E]">{formatUsd(tickingYield, ethPrice)}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-[10px] font-bold uppercase tracking-[0.1em] text-[#56565E] mb-1">Total Value</p>
                      <p className="font-mono text-[#EBEBEF] font-bold text-lg">
                        {(vaultSharesNum + tickingYield).toFixed(6)} <span className="text-xs">WETH</span>
                      </p>
                      <p className="text-[10px] font-mono text-[#56565E]">{formatUsd(vaultSharesNum + tickingYield, ethPrice)}</p>
                    </div>
                  </div>
                </div>

                {/* Strategy Allocation */}
                <p className="stat-label mb-3">Strategy Allocation</p>
                <div className="space-y-2">
                  <div className="card-elevated p-3 flex justify-between items-center">
                    <span className="font-mono text-sm text-[#EBEBEF] font-bold">Vault Reserves</span>
                    <span className="font-mono text-sm text-[#8B8B93]">
                      {vaultWethBalance ? Number(toEther(vaultWethBalance)).toFixed(4) : "0.0000"} WETH
                    </span>
                  </div>
                  <div className="bg-[rgba(0,255,178,0.04)] border border-[rgba(0,255,178,0.1)] rounded-xl p-3 flex justify-between items-center">
                    <div className="flex items-center gap-2">
                      <div className="w-2 h-2 rounded-full bg-[#00FFB2] animate-pulse" />
                      <span className="font-mono text-sm text-[#00FFB2] font-bold">Lido (Active)</span>
                    </div>
                    <span className="font-mono text-sm text-[#00FFB2]">
                      {strategyTotalValue ? Number(toEther(strategyTotalValue)).toFixed(4) : "0.0000"} WETH
                    </span>
                  </div>
                  {currentEthPct !== undefined && (
                    <div className="card-elevated p-3 flex justify-between items-center">
                      <span className="text-xs text-[#56565E] font-semibold">ETH Allocation</span>
                      <span className="font-mono text-xs text-[#8B8B93] font-bold">{ethPctDisplay}%</span>
                    </div>
                  )}
                </div>
              </div>
            </AnimateOnScroll>

            {/* PayEmbed — Buy ETH directly */}
            <AnimateOnScroll animation="fadeUp" delay={0.2}>
              <div className="glass-card p-8">
                <div className="flex items-center justify-between mb-4">
                  <p className="stat-label !mb-0">Fund Wallet</p>
                  <button
                    onClick={() => setShowPayEmbed(!showPayEmbed)}
                    className="text-xs font-bold text-[#00FFB2] hover:text-[#00CC8E] transition"
                  >
                    {showPayEmbed ? "Hide" : "Buy ETH"}
                  </button>
                </div>
                {showPayEmbed ? (
                  <PayEmbed
                    client={client}
                    theme={oszillorTheme}
                    payOptions={{
                      mode: "fund_wallet",
                      metadata: { name: "Fund OSZILLOR Wallet" },
                      prefillBuy: {
                        chain: sepolia,
                        amount: "0.01",
                      },
                    }}
                  />
                ) : (
                  <p className="text-sm text-[#56565E]">
                    Buy ETH directly with card or crypto to fund your vault deposits.
                  </p>
                )}
              </div>
            </AnimateOnScroll>

            {/* Recent Events */}
            {sortedEvents.length > 0 && (
              <AnimateOnScroll animation="fadeUp" delay={0.25}>
                <div className="glass-card p-8">
                  <p className="stat-label mb-3">Recent Activity</p>
                  <div className="space-y-2 font-mono text-xs">
                    {sortedEvents.map((evt, idx) => (
                      <div key={idx} className="flex items-center justify-between p-2 rounded-lg hover:bg-[#111113] transition">
                        <div className="flex items-center gap-2">
                          <div className="w-1.5 h-1.5 rounded-full bg-[#3B82F6]" />
                          <span className="text-[#56565E]">#{evt.blockNumber.toString()}</span>
                        </div>
                        <span className="text-[#00FFB2] font-bold">
                          +{Number(toEther((evt.args as unknown as { assets: bigint }).assets)).toFixed(4)} WETH
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              </AnimateOnScroll>
            )}
          </div>
        </div>

        {/* ── Contract Addresses ──────────────────────── */}
        <div className="mt-12 pt-8 border-t border-[#232326] flex flex-wrap justify-center gap-x-8 gap-y-2 text-center">
          <AddressDisplay address={VAULT_ADDRESS} label="Vault" />
          <AddressDisplay address={WETH_ADDRESS} label="WETH" />
          <AddressDisplay address={STRATEGY_ADDRESS} label="Strategy" />
        </div>
      </main>

      {/* ── Floating AI Terminal ─────────────────────── */}
      {isPanicking && (
        <div className="fixed bottom-6 right-6 w-[26rem] terminal z-50 shadow-2xl shadow-black/50" style={{ animation: "fade-in-up 0.3s ease-out" }}>
          <div className="terminal-header">
            <span className="text-[10px] tracking-[0.15em] text-[#00FFB2] font-bold uppercase">OSZILLOR AI FEED</span>
            <div className="terminal-dots">
              <span className="bg-[#FF3B5C] animate-pulse" />
            </div>
          </div>
          <div className="terminal-body h-56 overflow-y-auto space-y-2 flex flex-col justify-end">
            {mockLogs.map((log, i) => (
              <div key={i} className={log.includes("FATAL") || log.includes("DIRECTIVE") ? "text-[#FF3B5C] font-bold" : ""}>
                {log}
              </div>
            ))}
            <span className="w-2 h-4 bg-[#00FFB2]/70 animate-pulse inline-block mt-1" />
          </div>
        </div>
      )}
    </div>
  );
}
