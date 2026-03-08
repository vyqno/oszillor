"use client";

import Link from "next/link";
import { useState, useEffect } from "react";
import { ConnectButton, useActiveAccount, useReadContract, TransactionButton } from "thirdweb/react";
import { prepareContractCall, toWei, toEther } from "thirdweb";
import { client } from "@/client";
import { vaultContract, wethContract, vaultAbi, erc20Abi, VAULT_ADDRESS, STRATEGY_ADDRESS } from "@/lib/contracts";
import confetti from "canvas-confetti";

function Logo() {
  return (
    <div className="flex items-center gap-2">
      <div className="grid size-9 place-items-center rounded-2xl bg-[#2563eb]/10 ring-1 ring-[#2563eb]/20">
        <svg viewBox="0 0 24 24" className="size-4 text-[#2563eb]" fill="none">
          <path d="M4 12L12 4l3 3-5 5 5 5-3 3-8-8z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M14 4l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
      <div className="text-xl font-bold tracking-tight text-[#0a0f1e]">oszillor</div>
    </div>
  );
}

export default function DashboardPage() {
  const account = useActiveAccount();
  const [activeTab, setActiveTab] = useState<"deposit" | "withdraw">("deposit");
  const [amount, setAmount] = useState("");
  const [isPanicking, setIsPanicking] = useState(false);
  const [mockLogs, setMockLogs] = useState<string[]>([]);
  const [tickingYield, setTickingYield] = useState(0);
  
  useEffect(() => {
    if (!isPanicking) {
      setMockLogs([]);
      return;
    }
    const logs = [
      "> [Oszillor AI] Ingesting real-time HTTP streams...",
      "> [Oszillor AI] Scanning DefiLlama reserve ratios...",
      "> ------------------------------------------------",
      "> [Oszillor AI] Sentiment Analysis :: FATAL PANIC",
      "> [Oszillor AI] Exploit Probability :: 98.4%",
      "> [Oszillor AI] Risk Vector :: Lido ETH Depeg",
      "> ------------------------------------------------",
      "> [Oszillor AI] DIRECTIVE: EMIT_PAUSE_AND_WITHDRAW",
      "> [SYSTEM] Vault Paused. Funds routing to safety."
    ];
    let i = 0;
    setMockLogs(["> [SYSTEM] Initializing Risk Scanner..."]);
    const interval = setInterval(() => {
      if (i < logs.length) {
        setMockLogs(prev => [...prev, logs[i]]);
        i++;
      } else {
        clearInterval(interval);
      }
    }, 1200);
    return () => clearInterval(interval);
  }, [isPanicking]);

  const { data: totalAssets } = useReadContract({
    contract: vaultContract,
    method: vaultAbi[1],
    params: [],
  });
  const { data: isPaused } = useReadContract({
    contract: vaultContract,
    method: vaultAbi[2],
    params: [],
  });
  const { data: allowance } = useReadContract({
    contract: wethContract,
    method: erc20Abi[1],
    params: [account?.address || "0x0000000000000000000000000000000000000000", VAULT_ADDRESS],
  });
  const { data: wethBalance } = useReadContract({
    contract: wethContract,
    method: erc20Abi[2],
    params: [account?.address || "0x0000000000000000000000000000000000000000"],
  });
  const { data: vaultShares } = useReadContract({
    contract: vaultContract,
    method: erc20Abi[2],
    params: [account?.address || "0x0000000000000000000000000000000000000000"],
  });
  const { data: vaultWethBalance } = useReadContract({
    contract: wethContract,
    method: erc20Abi[2],
    params: [VAULT_ADDRESS],
  });
  const { data: strategyWethBalance } = useReadContract({
    contract: wethContract,
    method: erc20Abi[2],
    params: [STRATEGY_ADDRESS],
  });

  const amountWei = amount && !isNaN(Number(amount)) ? toWei(amount) : BigInt(0);
  const needsApproval = allowance !== undefined && allowance < amountWei && activeTab === "deposit";
  const tvl = totalAssets ? Number(toEther(totalAssets)).toFixed(4) : "0.0000";
  const formattedWethBalance = wethBalance ? Number(toEther(wethBalance)).toFixed(4) : "0.0000";
  const formattedVaultShares = vaultShares ? Number(toEther(vaultShares)).toFixed(4) : "0.0000";
  const vaultSharesNum = vaultShares ? Number(toEther(vaultShares)) : 0;
  
  useEffect(() => {
    if (vaultSharesNum === 0) return;
    const yieldPerSec = vaultSharesNum * 0.0642 / 31536000;
    const interval = setInterval(() => {
      setTickingYield(prev => prev + yieldPerSec / 10);
    }, 100);
    return () => clearInterval(interval);
  }, [vaultSharesNum]);

  const effectiveIsPaused = isPaused || isPanicking;

  return (
    <main className="min-h-screen bg-[#f5f7ff] text-[#0a0f1e] pb-16 pt-6 sm:px-8 lg:px-12">
      <div className="mx-auto max-w-6xl px-4">
        
        {/* Header */}
        <header className="flex items-center justify-between mb-12">
          <Logo />
          <div className="flex items-center gap-6">
            <nav className="hidden md:flex items-center gap-4 mr-4">
               <Link href="/dashboard" className="text-sm font-bold text-[#2563eb] border-b-2 border-[#2563eb] pb-1">Dashboard</Link>
               <Link href="/portfolio" className="text-sm font-semibold text-[#6b7280] hover:text-[#0a0f1e] transition">Portfolio</Link>
            </nav>
            <button 
              onClick={() => setIsPanicking(!isPanicking)}
              className="hidden md:flex text-[10px] uppercase tracking-widest font-bold text-red-500 bg-red-50 hover:bg-red-100 px-3 py-1.5 rounded-lg transition-colors items-center gap-1.5 border border-red-100"
            >
              <div className={`w-2 h-2 rounded-full bg-red-500 ${isPanicking ? 'animate-pulse' : ''}`} />
              {isPanicking ? "RESET STATE" : "SIMULATE PANIC"}
            </button>
            <Link href="/" className="text-sm font-semibold text-[#6b7280] hover:text-[#0a0f1e] transition">Exit App</Link>
            <ConnectButton 
              client={client} 
              theme="light"
              connectButton={{ className: "btn-primary !text-sm !font-semibold !px-6 !py-3 !text-white" }}
            />
          </div>
        </header>

        <div className="mb-8 text-center sm:text-left">
           <h1 className="text-3xl sm:text-4xl font-bold text-[#0d1630]">Vault Dashboard</h1>
           <p className="mt-2 text-sm text-[#6b7280]">Manage your deposits and monitor strategy yield.</p>
        </div>

        {/* Top Status Panels */}
        <div className="grid gap-6 md:grid-cols-[1fr_1fr_1fr] mb-8">
          <div className="white-card rounded-3xl p-6 relative overflow-hidden">
            <div className="flex justify-between items-start">
               <div>
                  <p className="text-xs font-bold uppercase tracking-widest text-[#6b7280] mb-2">Protocol TVL</p>
                  <p className="text-3xl font-extrabold text-[#0d1630] font-mono tracking-tight">{tvl}</p>
               </div>
               <div className="grid size-10 place-items-center rounded-xl bg-[#edf2ff] text-[#3b5bdb]">
                 <span className="font-bold text-sm">WETH</span>
               </div>
            </div>
            {/* mock positive change */}
            <p className="mt-4 flex items-center gap-1 text-sm font-semibold text-emerald-500">
               <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 10l7-7m0 0l7 7m-7-7v18"></path></svg>
               +1.24% <span className="text-[#6b7280] font-normal ml-1">Today</span>
            </p>
          </div>
          
          <div className="white-card rounded-3xl p-6 relative overflow-hidden">
            <div className="flex justify-between items-start">
               <div>
                  <p className="text-xs font-bold uppercase tracking-widest text-[#6b7280] mb-2">Target Yield</p>
                  <p className="text-3xl font-extrabold text-[#0d1630] font-mono tracking-tight">6.42<span className="text-xl text-[#0d1630]/60 font-sans">%</span></p>
               </div>
               <div className="grid size-10 place-items-center rounded-xl bg-emerald-50 text-emerald-500">
                 <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"></path></svg>
               </div>
            </div>
            <p className="mt-4 flex items-center gap-1 text-sm font-semibold text-emerald-500">
               <svg className="w-4 h-4 text-emerald-500 animate-[spin_3s_linear_infinite]" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path></svg>
               +{tickingYield.toFixed(8)} <span className="text-[#6b7280] font-normal ml-1">Live yield (WETH)</span>
            </p>
          </div>

          <div className="white-card rounded-3xl p-6 relative overflow-hidden">
             <div className="flex justify-between items-start">
                <div>
                  <p className="text-xs font-bold uppercase tracking-widest text-[#6b7280] mb-2">Risk Gatekeeper</p>
                  <div className="flex items-center gap-2 mt-1">
                    {effectiveIsPaused === undefined ? (
                      <p className="text-2xl font-bold text-[#0d1630] animate-pulse">Syncing...</p>
                    ) : effectiveIsPaused ? (
                      <>
                        <div className="h-3 w-3 rounded-full bg-red-500 animate-pulse" />
                        <p className="text-2xl font-bold text-red-500 tracking-tight">PAUSED</p>
                      </>
                    ) : (
                      <>
                        <div className="h-3 w-3 rounded-full bg-emerald-500" />
                        <p className="text-2xl font-bold text-[#0d1630] tracking-tight">SECURE</p>
                      </>
                    )}
                  </div>
                </div>
                <div className="grid size-10 place-items-center rounded-xl bg-purple-50 text-purple-600">
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"></path></svg>
                </div>
             </div>
             <div className="mt-4 w-full bg-[#f3f4f6] rounded-full h-1.5 overflow-hidden flex">
                <div className={`h-full w-[100%] rounded-full ${effectiveIsPaused ? 'bg-red-500' : 'bg-emerald-500 animate-pulse'}`} />
             </div>
             <p className={`mt-2 text-xs font-medium ${effectiveIsPaused ? 'text-red-500 animate-pulse' : 'text-[#6b7280]'}`}>{effectiveIsPaused ? 'EMERGENCY SHUTDOWN' : 'Real-time scans active'}</p>
          </div>
        </div>

        {/* Main Interface */}
        <div className="grid gap-6 lg:grid-cols-[1.5fr_1fr]">
          
          {/* Interaction Console */}
          <section className="white-card rounded-3xl p-8">
             <div className="flex items-center gap-8 border-b border-[#e5e7eb] pb-6 mb-8">
                <button 
                  onClick={() => setActiveTab("deposit")}
                  className={`text-sm font-bold uppercase tracking-wider pb-6 -mb-[25px] border-b-2 transition-all duration-300 ${activeTab === "deposit" ? "text-[#2563eb] border-[#2563eb]" : "text-[#6b7280] border-transparent hover:text-[#0d1630]"}`}
                >
                  Deposit
                </button>
                <button 
                  onClick={() => setActiveTab("withdraw")}
                  className={`text-sm font-bold uppercase tracking-wider pb-6 -mb-[25px] border-b-2 transition-all duration-300 ${activeTab === "withdraw" ? "text-[#2563eb] border-[#2563eb]" : "text-[#6b7280] border-transparent hover:text-[#0d1630]"}`}
                >
                  Withdraw
                </button>
             </div>

             <div>
                <h2 className="text-2xl font-bold text-[#0d1630] mb-2 tracking-tight">
                  {activeTab === "deposit" ? "Route Liquidity" : "Reclaim Liquidity"}
                </h2>
                <p className="text-sm text-[#6b7280] mb-8 leading-relaxed max-w-md">
                  {activeTab === "deposit" 
                    ? "Deposit WETH into the autonomous strategy. Yield generation begins instantly."
                    : "Withdraw your underlying WETH and accrued yield from the OSZILLOR strategy."}
                </p>

                {/* Input Field */}
                <div className="bg-[#f9fafb] border border-[#e5e7eb] rounded-2xl p-4 mb-8 flex items-center justify-between">
                  <div className="flex-1">
                     <p className="text-[10px] font-bold uppercase tracking-widest text-[#6b7280] mb-1 pl-2">Amount</p>
                     <input 
                        type="number"
                        value={amount}
                        onChange={(e) => {
                          const val = e.target.value.replace(/-/g, "");
                          setAmount(val);
                        }}
                        onKeyDown={(e) => {
                          if (e.key === "-" || e.key === "e" || e.key === "E") e.preventDefault();
                        }}
                        placeholder="0.00"
                        className="w-full bg-transparent text-4xl sm:text-5xl font-extrabold text-[#0d1630] placeholder:text-[#d1d5db] focus:outline-none focus:ring-0 pl-2 font-mono [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                        min="0"
                        step="0.01"
                      />
                  </div>
                  <div className="flex flex-col items-end justify-center pr-2 gap-3">
                     <div className="flex flex-col items-end gap-1">
                        <p className="text-[11px] font-semibold text-[#6b7280]">
                          Balance: <span className="text-[#0d1630] font-bold">{account ? (activeTab === "deposit" ? formattedWethBalance : formattedVaultShares) : "--"} {activeTab === "deposit" ? "WETH" : "oszWETH"}</span>
                        </p>
                        {account && activeTab === "deposit" && Number(formattedWethBalance) < 0.05 && (
                          <TransactionButton
                            transaction={() => prepareContractCall({ contract: wethContract, method: erc20Abi[3], params: [account.address, toWei("0.05")] })}
                            className="!bg-transparent !p-0 !min-w-0 !h-auto !text-[#2563eb] hover:!text-[#1d4ed8] !text-[10px] !font-bold transition-colors !shadow-none"
                          >
                            Claim 0.05 Test WETH
                          </TransactionButton>
                        )}
                     </div>
                     <div className="flex items-center gap-2">
                         <button 
                          onClick={() => {
                            if (account) {
                              if (activeTab === "deposit" && wethBalance) {
                                setAmount(toEther(wethBalance));
                              } else if (activeTab === "withdraw" && vaultShares) {
                                setAmount(toEther(vaultShares));
                              } else {
                                setAmount("0.00");
                              }
                            } else {
                              setAmount("1.0");
                            }
                          }}
                          className="px-3 py-1.5 rounded-lg bg-[#edf2ff] hover:bg-[#dfe7ff] text-xs font-bold text-[#2563eb] transition-colors h-10 flex items-center"
                        >
                          MAX
                        </button>
                        <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-white border border-[#e5e7eb] shadow-sm h-10">
                          <div className={`w-5 h-5 rounded-full bg-gradient-to-tr ${activeTab === "deposit" ? 'from-[#3b82f6] to-[#60a5fa] border-[#bfdbfe]' : 'from-[#8b5cf6] to-[#c4b5fd] border-[#ddd6fe]'} border`} />
                          <span className="text-sm font-bold text-[#0d1630]">{activeTab === "deposit" ? "WETH" : "oszWETH"}</span>
                        </div>
                     </div>
                  </div>
                </div>

                {/* Action Button */}
                {!account ? (
                  <div className="w-full py-4 text-center rounded-2xl border border-dashed border-[#d1d5db] bg-[#f9fafb] text-sm font-semibold text-[#6b7280]">
                    Please connect your wallet to interact
                  </div>
                ) : needsApproval ? (
                   <TransactionButton
                      transaction={() => prepareContractCall({ contract: wethContract, method: erc20Abi[0], params: [VAULT_ADDRESS, amountWei] })}
                      className="!w-full !rounded-2xl !bg-[#2563eb] hover:!bg-[#1d4ed8] !text-white !font-bold !text-base !py-4 !shadow-md transition-all"
                    >
                      Approve WETH Spend
                   </TransactionButton>
                ) : (
                   <TransactionButton
                       transaction={() => {
                        if (activeTab === "deposit") {
                          return prepareContractCall({ contract: vaultContract, method: vaultAbi[0], params: [amountWei, account.address] });
                        } else {
                          // withdraw(uint256 assets, address receiver, address owner)
                          return prepareContractCall({ contract: vaultContract, method: vaultAbi[3], params: [amountWei, account.address, account.address] });
                        }
                      }}
                      onTransactionConfirmed={() => {
                        confetti({
                          particleCount: 100,
                          spread: 70,
                          origin: { y: 0.6 },
                          colors: ['#2563eb', '#3b82f6', '#10b981', '#34d399']
                        });
                        setAmount("");
                      }}
                      disabled={effectiveIsPaused || !amount || amountWei === BigInt(0) || (activeTab === "deposit" && wethBalance !== undefined && amountWei > wethBalance) || (activeTab === "withdraw" && vaultShares !== undefined && amountWei > vaultShares)}
                      className="!w-full !rounded-2xl !bg-[#2563eb] hover:!bg-[#1d4ed8] !text-white !font-bold !text-base !py-4 transition-all disabled:!opacity-50 disabled:!cursor-not-allowed !shadow-md"
                    >
                      {activeTab === "deposit" ? "Execute Deposit" : "Execute Withdrawal"}
                   </TransactionButton>
                )}
                
                {amount && amountWei > BigInt(0) && activeTab === "deposit" && wethBalance !== undefined && amountWei > wethBalance && (
                  <p className="mt-3 text-sm text-red-500 font-bold text-center">Insufficient WETH balance.</p>
                )}
                {amount && amountWei > BigInt(0) && activeTab === "withdraw" && vaultShares !== undefined && amountWei > vaultShares && (
                  <p className="mt-3 text-sm text-red-500 font-bold text-center">Insufficient oszWETH balance.</p>
                )}
                
                {effectiveIsPaused && (
                  <div className="mt-4 flex items-start gap-2 text-red-600 bg-red-50 p-4 rounded-2xl border border-red-100">
                    <svg viewBox="0 0 24 24" className="w-5 h-5 shrink-0" fill="none" stroke="currentColor">
                       <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                    </svg>
                    <p className="text-sm font-medium">Smart contracts are currently safeguarded. Operations are halted until the AI Gatekeeper resolves the anomaly.</p>
                  </div>
                )}
             </div>
          </section>

          {/* Right: Chart Mock */}
          <section className="white-card rounded-3xl p-8 flex flex-col items-center justify-center relative overflow-hidden text-center">
             <div className="absolute top-0 right-0 w-64 h-64 bg-[#edf2ff] rounded-full blur-3xl opacity-50 -z-10" />
             <div className="absolute bottom-0 left-0 w-48 h-48 bg-[#edf2ff] rounded-full blur-3xl opacity-50 -z-10" />
             
             <div className="w-16 h-16 bg-[#edf2ff] text-[#2563eb] rounded-2xl flex items-center justify-center mx-auto mb-6">
               <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"></path></svg>
             </div>
             
             <h3 className="text-xl font-bold text-[#0d1630] mb-2">Automated Yield Engine</h3>
             <p className="text-sm text-[#6b7280] max-w-sm">
               Your WETH is continuously deployed across safe strategies to ensure optimal risk-adjusted APY. 
             </p>

             <div className="mt-8 w-full">
               <div className="flex justify-between text-[10px] font-bold text-[#6b7280] mb-2 px-2 uppercase tracking-widest">
                 <span>Your Live Position</span>
               </div>
               <div className="bg-[#f9fafb] border border-[#e5e7eb] rounded-xl p-4 flex justify-between items-center transition-all hover:border-[#d1d5db] mb-6 shadow-inner relative overflow-hidden">
                 <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-100 rounded-full blur-2xl opacity-50 -z-10" />
                 <div className="flex flex-col text-left">
                    <span className="text-[10px] font-bold text-[#6b7280] uppercase tracking-wider mb-1">Unrealized Yield</span>
                    <span className="font-mono text-emerald-600 font-extrabold text-lg tracking-tight">+{tickingYield.toFixed(8)} <span className="text-xs">WETH</span></span>
                 </div>
                 <div className="flex flex-col text-right">
                    <span className="text-[10px] font-bold text-[#6b7280] uppercase tracking-wider mb-1">Total Value</span>
                    <span className="font-mono text-[#0d1630] font-bold text-lg tracking-tight">{(vaultSharesNum + tickingYield).toFixed(6)} <span className="text-xs">WETH</span></span>
                 </div>
               </div>

               <div className="flex justify-between text-xs font-bold text-[#6b7280] mb-2 px-2 uppercase tracking-wide">
                 <span>Strategy Allocation</span>
               </div>
               <div className="flex flex-col gap-2">
                 <div className="bg-[#f9fafb] border border-[#e5e7eb] rounded-xl p-4 flex justify-between items-center transition-all hover:border-[#d1d5db]">
                   <span className="font-mono text-[#0d1630] font-bold tracking-tight">Vault Reserves</span>
                   <span className="font-mono text-[#6b7280] font-bold">{vaultWethBalance ? Number(toEther(vaultWethBalance)).toFixed(4) : "0.0000"} WETH</span>
                 </div>
                 <div className="bg-emerald-50 border border-emerald-100 rounded-xl p-4 flex justify-between items-center transition-all shadow-sm">
                   <div className="flex items-center gap-2">
                      <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></div>
                      <span className="font-mono text-emerald-800 font-bold tracking-tight">Lido (Active)</span>
                   </div>
                   <span className="font-mono text-emerald-600 font-bold">{strategyWethBalance ? Number(toEther(strategyWethBalance)).toFixed(4) : "0.0000"} WETH</span>
                 </div>
               </div>
             </div>
          </section>

        </div>
      </div>

      {/* Floating AI Terminal */}
      {isPanicking && (
        <div className="fixed bottom-6 right-6 w-[28rem] bg-[#030B1A] border border-[#1D4ED8]/30 rounded-2xl shadow-2xl overflow-hidden z-50 flex flex-col font-mono text-xs sm:text-sm animate-in slide-in-from-bottom-5 fade-in duration-300">
          <div className="bg-[#0a1128] px-4 py-3 flex justify-between items-center border-b border-[#1D4ED8]/20">
            <span className="uppercase tracking-widest text-[#60a5fa] font-bold">OSZILLOR AI SECURE FEED</span>
            <div className="flex gap-1.5">
               <div className="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse" />
            </div>
          </div>
          <div className="p-5 text-[#60a5fa] h-56 overflow-y-auto space-y-2.5 flex flex-col justify-end leading-relaxed">
             {mockLogs.filter(Boolean).map((log, i) => (
               <div key={i} className={log.includes("FATAL") || log.includes("DIRECTIVE") ? "text-red-400 font-bold" : ""}>
                 {log}
               </div>
             ))}
             <div className="animate-pulse w-2 h-4 bg-[#60a5fa] mt-1 inline-block" />
          </div>
        </div>
      )}
    </main>
  );
}
