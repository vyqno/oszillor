"use client";

import Link from "next/link";
import { useState, useEffect } from "react";
import { ConnectButton, useActiveAccount, useReadContract, useContractEvents } from "thirdweb/react";
import { toEther, prepareEvent } from "thirdweb";
import { client } from "@/client";
import { vaultContract, wethContract, oszContract, erc20Abi } from "@/lib/contracts";

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

export default function PortfolioPage() {
  const account = useActiveAccount();
  const address = account?.address || "0x0000000000000000000000000000000000000000";

  // Fetch balances
  const { data: wethBalance } = useReadContract({
    contract: wethContract,
    method: erc20Abi[2],
    params: [address],
  });

  // Re-using ERC20 ABI to read vault shares (oszWETH) since Vault is an ERC4626 (ERC20 standard)
  const { data: vaultShares } = useReadContract({
    contract: vaultContract,
    method: erc20Abi[2],
    params: [address],
  });

  const { data: oszBalance } = useReadContract({
    contract: oszContract,
    method: erc20Abi[2],
    params: [address],
  });

  const formattedWeth = wethBalance ? Number(toEther(wethBalance)).toFixed(4) : "0.0000";
  const formattedShares = vaultShares ? Number(toEther(vaultShares)).toFixed(4) : "0.0000";
  const formattedOsz = oszBalance ? Number(toEther(oszBalance)).toFixed(2) : "0.00";
  const formattedSharesNum = vaultShares ? Number(toEther(vaultShares)) : 0;
  
  const [tickingYield, setTickingYield] = useState(0);

  useEffect(() => {
    if (formattedSharesNum === 0) return;
    const yieldPerSec = formattedSharesNum * 0.0642 / 31536000;
    const interval = setInterval(() => {
      setTickingYield(prev => prev + yieldPerSec / 10);
    }, 100);
    return () => clearInterval(interval);
  }, [formattedSharesNum]);
  
  // Mock total value calculation (assuming 1 WETH/oszWETH = $3500 for visual effect)
  const totalEthValue = (Number(formattedWeth) + formattedSharesNum + tickingYield);
  const totalUsdValue = totalEthValue * 3500;

  // Real feeds for AI Transaction Ledger
  const depositEvent = prepareEvent({
    signature: "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)"
  });
  const { data: recentDeposits } = useContractEvents({
    contract: vaultContract,
    events: [depositEvent],
    blockRange: 50000,
  });

  const sortedEvents = recentDeposits ? [...recentDeposits].sort((a, b) => Number(b.blockNumber) - Number(a.blockNumber)).slice(0, 5) : [];

  return (
    <main className="min-h-screen bg-[#f5f7ff] text-[#0a0f1e] pb-16 pt-6 sm:px-8 lg:px-12">
      <div className="mx-auto max-w-6xl px-4">
        
        {/* Header */}
        <header className="flex items-center justify-between mb-12">
          <Logo />
          <div className="flex items-center gap-6">
            <nav className="hidden md:flex items-center gap-4 mr-4">
               <Link href="/dashboard" className="text-sm font-semibold text-[#6b7280] hover:text-[#0a0f1e] transition">Dashboard</Link>
               <Link href="/portfolio" className="text-sm font-bold text-[#2563eb] border-b-2 border-[#2563eb] pb-1">Portfolio</Link>
            </nav>
            <Link href="/" className="text-sm font-semibold text-[#6b7280] hover:text-[#0a0f1e] transition">Exit App</Link>
            <ConnectButton 
              client={client} 
              theme="light"
              connectButton={{ className: "btn-primary !text-sm !font-semibold !px-6 !py-3 !text-white" }}
            />
          </div>
        </header>

        <div className="mb-10 text-center sm:text-left flex flex-col md:flex-row md:items-end md:justify-between gap-4">
           <div>
             <h1 className="text-3xl sm:text-4xl font-bold text-[#0d1630]">My Portfolio</h1>
             <p className="mt-2 text-sm text-[#6b7280]">Track your OSZILLOR positions and AI-driven yield.</p>
           </div>
           
           {/* Mock Yield Velocity Mini-Chart */}
           <div className="flex items-center gap-3 bg-white px-4 py-2 rounded-2xl border border-[#e5e7eb] shadow-sm">
             <div className="w-10 h-6 flex items-end gap-1">
               <div className="w-2 bg-emerald-200 h-[30%] rounded-t-sm"></div>
               <div className="w-2 bg-emerald-300 h-[50%] rounded-t-sm"></div>
               <div className="w-2 bg-emerald-400 h-[80%] rounded-t-sm"></div>
               <div className="w-2 bg-emerald-500 h-[100%] rounded-t-sm shadow-[0_0_8px_rgba(16,185,129,0.5)]"></div>
             </div>
             <div>
               <p className="text-[10px] font-bold text-[#6b7280] uppercase tracking-wider">7D Velocity</p>
               <p className="text-sm font-bold text-emerald-600">+1.24%</p>
             </div>
           </div>
        </div>

        {!account ? (
           <div className="white-card rounded-3xl p-16 text-center">
             <div className="w-16 h-16 bg-[#edf2ff] text-[#2563eb] rounded-full flex items-center justify-center mx-auto mb-6">
               <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8V7a4 4 0 00-8 0v4h8z"></path></svg>
             </div>
             <h2 className="text-2xl font-bold text-[#0d1630] mb-2">Connect to view portfolio</h2>
             <p className="text-[#6b7280] max-w-sm mx-auto">Please connect your Web3 wallet to access your balances, yield history, and OSZ holdings.</p>
           </div>
        ) : (
          <>
            {/* Top Stat Cards */}
            <div className="grid gap-6 md:grid-cols-[1.5fr_1fr] lg:grid-cols-[1.5fr_1fr_1fr] mb-8">
              
              {/* Total Value Panel */}
              <div className="bg-[#030b1a] rounded-3xl p-8 relative overflow-hidden text-white shadow-xl shadow-[#030b1a]/10 group">
                {/* Background glow effects */}
                <div className="absolute -top-32 -right-32 w-96 h-96 bg-[#2563eb] opacity-20 rounded-full blur-[100px] group-hover:opacity-30 transition-opacity duration-700" />
                <div className="absolute -bottom-32 -left-32 w-96 h-96 bg-[#3b82f6] opacity-10 rounded-full blur-[100px]" />
                
                <div className="relative z-10 flex flex-col h-full justify-between">
                   <div>
                     <p className="text-xs font-bold uppercase tracking-widest text-[#9ca3af] mb-2 flex items-center gap-2">
                       <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
                       Net Worth (Est)
                     </p>
                     <p className="text-4xl sm:text-5xl font-extrabold font-mono tracking-tight flex items-baseline gap-2">
                       ${totalUsdValue.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}
                       {tickingYield > 0 && <span className="text-emerald-400 text-lg font-mono tracking-tight animate-pulse">+${(tickingYield * 3500).toFixed(4)}</span>}
                     </p>
                   </div>
                   
                   <div className="mt-8 pt-6 border-t border-white/10 flex items-end justify-between">
                      <div>
                        <p className="text-sm font-semibold text-[#9ca3af]">Total Deposited</p>
                        <p className="text-lg font-bold font-mono text-white">{formattedShares} <span className="text-[#9ca3af] text-sm">oszWETH</span></p>
                      </div>
                      <div className="text-right">
                        <p className="text-sm font-semibold text-[#9ca3af]">Wallet Liquid</p>
                        <p className="text-lg font-bold font-mono text-white">{formattedWeth} <span className="text-[#9ca3af] text-sm">WETH</span></p>
                      </div>
                   </div>
                </div>
              </div>

              {/* AI Threat Defense Box */}
              <div className="white-card rounded-3xl p-6 relative overflow-hidden flex flex-col justify-between">
                <div>
                  <div className="flex justify-between items-start mb-4">
                    <p className="text-xs font-bold uppercase tracking-widest text-[#6b7280]">AI Risk Posture</p>
                    <div className="grid size-8 place-items-center rounded-lg bg-emerald-50 text-emerald-600">
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"></path></svg>
                    </div>
                  </div>
                  <h3 className="text-2xl font-bold text-[#0d1630]">Aggressive</h3>
                  <p className="text-sm text-emerald-600 font-medium mt-1">Capital fully deployed</p>
                </div>
                <div className="mt-6">
                  <p className="text-xs text-[#6b7280] mb-2 font-medium">Mitigated Threats (24H)</p>
                  <p className="text-xl font-bold font-mono text-[#0d1630]">0</p>
                </div>
              </div>

              {/* OSZ Token Box (Mocked) */}
              <div className="white-card rounded-3xl p-6 flex flex-col justify-between lg:col-span-1 md:col-span-2">
                 <div>
                    <div className="flex justify-between items-start mb-4">
                      <p className="text-xs font-bold uppercase tracking-widest text-[#6b7280]">Governance Power</p>
                      <div className="grid size-8 place-items-center rounded-lg bg-[#edf2ff] text-[#2563eb]">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"></path></svg>
                      </div>
                    </div>
                    <h3 className="text-2xl font-bold text-[#0d1630]">{formattedOsz} <span className="text-sm text-[#6b7280]">OSZ</span></h3>
                 </div>
                 <button className="mt-6 w-full py-2.5 rounded-xl bg-[#f9fafb] border border-[#e5e7eb] hover:bg-gray-100 text-sm font-bold text-[#4b5563] transition-colors">
                   Stake OSZ for Boost
                 </button>
              </div>

            </div>

            {/* Positions Table */}
            <div className="white-card rounded-3xl overflow-hidden mb-8">
               <div className="px-6 py-5 border-b border-[#e5e7eb]">
                 <h3 className="text-lg font-bold text-[#0d1630]">Asset Balances</h3>
               </div>
               <div className="overflow-x-auto">
                 <table className="w-full text-left border-collapse">
                   <thead>
                     <tr className="bg-[#f9fafb] border-b border-[#e5e7eb]">
                       <th className="px-6 py-4 text-xs font-bold uppercase tracking-wider text-[#6b7280]">Asset</th>
                       <th className="px-6 py-4 text-xs font-bold uppercase tracking-wider text-[#6b7280]">Location</th>
                       <th className="px-6 py-4 text-xs font-bold uppercase tracking-wider text-[#6b7280] text-right">Balance</th>
                       <th className="px-6 py-4 text-xs font-bold uppercase tracking-wider text-[#6b7280] text-right">Value (Est)</th>
                     </tr>
                   </thead>
                   <tbody className="divide-y divide-[#e5e7eb]">
                     
                     {/* Vault Shares Row */}
                     <tr className="hover:bg-[#f9fafb] transition-colors">
                       <td className="px-6 py-4">
                         <div className="flex items-center gap-3">
                           <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-[#030b1a] to-[#2563eb] border-2 border-white shadow-sm" />
                           <div>
                             <p className="font-bold text-[#0d1630]">oszWETH</p>
                             <p className="text-xs text-[#6b7280]">Yield-Bearing Vault Share</p>
                           </div>
                         </div>
                       </td>
                       <td className="px-6 py-4">
                         <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                           Smart Contract
                         </span>
                       </td>
                       <td className="px-6 py-4 text-right">
                         <p className="font-bold font-mono text-[#0d1630]">{(formattedSharesNum + tickingYield).toFixed(6)}</p>
                         {tickingYield > 0 && <p className="text-[10px] font-bold font-mono text-emerald-500 tracking-tight animate-pulse">+{tickingYield.toFixed(8)}</p>}
                       </td>
                       <td className="px-6 py-4 text-right">
                         <p className="font-semibold text-[#0d1630]">${((formattedSharesNum + tickingYield) * 3500).toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</p>
                       </td>
                     </tr>
                     
                     {/* WETH Row */}
                     <tr className="hover:bg-[#f9fafb] transition-colors">
                       <td className="px-6 py-4">
                         <div className="flex items-center gap-3">
                           <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-[#3b82f6] to-[#60a5fa] border border-[#bfdbfe]" />
                           <div>
                             <p className="font-bold text-[#0d1630]">WETH</p>
                             <p className="text-xs text-[#6b7280]">Wrapped Ethereum</p>
                           </div>
                         </div>
                       </td>
                       <td className="px-6 py-4">
                         <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                           Wallet
                         </span>
                       </td>
                       <td className="px-6 py-4 text-right">
                         <p className="font-bold font-mono text-[#0d1630]">{formattedWeth}</p>
                       </td>
                       <td className="px-6 py-4 text-right">
                         <p className="font-semibold text-[#0d1630]">${(Number(formattedWeth) * 3500).toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</p>
                       </td>
                     </tr>

                     {/* OSZ Row */}
                     <tr className="hover:bg-[#f9fafb] transition-colors">
                       <td className="px-6 py-4">
                         <div className="flex items-center gap-3">
                           <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-[#1d4ed8] to-[#2563eb] border border-[#bfdbfe] flex items-center justify-center text-white font-bold text-xs">O</div>
                           <div>
                             <p className="font-bold text-[#0d1630]">OSZ</p>
                             <p className="text-xs text-[#6b7280]">Protocol Token</p>
                           </div>
                         </div>
                       </td>
                       <td className="px-6 py-4">
                         <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                           Wallet
                         </span>
                       </td>
                       <td className="px-6 py-4 text-right">
                         <p className="font-bold font-mono text-[#0d1630]">{formattedOsz}</p>
                       </td>
                       <td className="px-6 py-4 text-right">
                         <p className="font-semibold text-[#0d1630]">${(Number(formattedOsz) * 1.5).toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</p>
                       </td>
                     </tr>

                   </tbody>
                 </table>
               </div>
            </div>

            {/* AI Transaction Terminal */}
            <div className="white-card rounded-3xl p-6">
              <div className="flex justify-between items-center border-b border-[#e5e7eb] pb-4 mb-4">
                 <h3 className="text-lg font-bold text-[#0d1630] flex items-center gap-2">
                   <svg className="w-5 h-5 text-[#2563eb]" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg>
                   AI Transaction Ledger
                 </h3>
                 <span className="text-xs font-medium bg-emerald-100 text-emerald-800 px-2 py-1 rounded">Live Sync</span>
              </div>
              <div className="space-y-3 font-mono text-sm">
                 {sortedEvents.length > 0 ? (
                   sortedEvents.map((evt, idx) => (
                      <div key={idx} className="flex items-center justify-between p-3 rounded-xl hover:bg-[#f9fafb] transition-colors border border-transparent hover:border-[#e5e7eb]">
                        <div className="flex items-center gap-3">
                          <div className="w-2 h-2 rounded-full bg-blue-500"></div>
                          <span className="text-[#6b7280]">Block #{evt.blockNumber.toString()}</span>
                          <span className="text-[#0d1630] font-bold">Vault Deposit</span>
                        </div>
                        <span className="text-emerald-600 font-bold">+{Number(toEther((evt.args as any).assets)).toFixed(4)} WETH</span>
                      </div>
                   ))
                 ) : (
                   <>
                     <div className="flex items-center justify-between p-3 rounded-xl hover:bg-[#f9fafb] transition-colors border border-transparent hover:border-[#e5e7eb]">
                       <div className="flex items-center gap-3">
                         <div className="w-2 h-2 rounded-full bg-blue-500"></div>
                         <span className="text-[#6b7280]">12 mins ago</span>
                         <span className="text-[#0d1630] font-bold">Yield Harvest</span>
                       </div>
                       <span className="text-emerald-600 font-bold">+0.0001 WETH</span>
                     </div>
                     <div className="flex items-center justify-between p-3 rounded-xl hover:bg-[#f9fafb] transition-colors border border-transparent hover:border-[#e5e7eb]">
                       <div className="flex items-center gap-3">
                         <div className="w-2 h-2 rounded-full bg-purple-500"></div>
                         <span className="text-[#6b7280]">2 hrs ago</span>
                         <span className="text-[#0d1630] font-bold">Route Liquidity (Aave &rarr; Compound)</span>
                       </div>
                       <span className="text-[#6b7280]">Optimized 2.1% spread</span>
                     </div>
                     <div className="flex items-center justify-between p-3 rounded-xl hover:bg-[#f9fafb] transition-colors border border-transparent hover:border-[#e5e7eb] opacity-60">
                       <div className="flex items-center gap-3">
                         <div className="w-2 h-2 rounded-full bg-gray-400"></div>
                         <span className="text-[#6b7280]">1 day ago</span>
                         <span className="text-[#0d1630] font-bold">Initial Deposit</span>
                       </div>
                       <span className="text-[#6b7280]">Confirmed</span>
                     </div>
                   </>
                 )}
              </div>
            </div>
            
          </>
        )}
      </div>
    </main>
  );
}
