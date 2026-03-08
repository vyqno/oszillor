"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton, useActiveAccount, useActiveWalletChain } from "thirdweb/react";
import { sepolia } from "thirdweb/chains";
import { client } from "@/client";
import { wallets } from "@/lib/wallets";
import { oszillorTheme } from "@/lib/theme";
import { WETH_ADDRESS } from "@/lib/contracts";

const navLinks = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/portfolio", label: "Portfolio" },
];

export function Header() {
  const pathname = usePathname();
  const account = useActiveAccount();
  const chain = useActiveWalletChain();
  const wrongChain = account && chain && chain.id !== sepolia.id;

  return (
    <header className="sticky top-0 z-50 border-b border-[rgba(255,255,255,0.04)] glass">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2.5 group">
            <div className="grid size-8 place-items-center rounded-lg bg-[rgba(0,255,178,0.1)] border border-[rgba(0,255,178,0.2)] group-hover:border-[rgba(0,255,178,0.4)] transition-colors">
              <svg viewBox="0 0 24 24" className="size-4 text-[#00FFB2]" fill="none">
                <path d="M4 12L12 4l3 3-5 5 5 5-3 3-8-8z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M14 4l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <span className="text-sm font-bold tracking-[0.15em] uppercase text-[#EBEBEF]">
              OSZILLOR
            </span>
          </Link>

          {/* Navigation */}
          <nav className="hidden md:flex items-center gap-1">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={`nav-link px-4 py-2 text-sm font-semibold rounded-lg transition-all ${
                  pathname === link.href
                    ? "text-[#00FFB2] bg-[rgba(0,255,178,0.08)]"
                    : "text-[#8B8B93] hover:text-[#EBEBEF] hover:bg-[#1C1C1F]"
                }`}
              >
                {link.label}
              </Link>
            ))}
          </nav>

          {/* Right side: chain indicator + connect */}
          <div className="flex items-center gap-3">
            {/* Chain indicator */}
            {account && (
              <div className={`hidden sm:flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-bold ${
                wrongChain
                  ? "bg-[rgba(255,59,92,0.1)] text-[#FF3B5C] border border-[rgba(255,59,92,0.2)]"
                  : "bg-[#1C1C1F] text-[#8B8B93] border border-[#232326]"
              }`}>
                <div className={`w-2 h-2 rounded-full ${wrongChain ? "bg-[#FF3B5C] animate-pulse" : "bg-[#00FFB2]"}`} />
                {wrongChain ? "Wrong Network" : "Sepolia"}
              </div>
            )}

            {/* thirdweb ConnectButton with OSZILLOR branding */}
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
              connectModal={{
                title: "Connect to OSZILLOR",
                size: "wide",
              }}
              connectButton={{
                label: "Connect Wallet",
                className: "!rounded-lg",
              }}
              detailsButton={{
                displayBalanceToken: {
                  [sepolia.id]: WETH_ADDRESS,
                },
              }}
            />
          </div>
        </div>
      </div>
    </header>
  );
}
