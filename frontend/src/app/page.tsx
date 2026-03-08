"use client";

import Link from "next/link";
import { ConnectButton } from "thirdweb/react";
import { sepolia } from "thirdweb/chains";
import { client } from "@/client";
import { wallets } from "@/lib/wallets";
import { oszillorTheme } from "@/lib/theme";
import { AnimateOnScroll } from "@/components/AnimateOnScroll";
import { ParallaxSection } from "@/components/ParallaxSection";
import { CountUp } from "@/components/CountUp";

const features = [
  {
    tag: "30s",
    title: "Real-Time Risk Scans",
    body: "CRE workflows execute every 30 seconds, pulling live off-chain telemetry from DefiLlama, CoinGecko, and news feeds.",
    animation: "fadeUp" as const,
    icon: (
      <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    ),
  },
  {
    tag: "AI",
    title: "Autonomous Defense",
    body: "If the AI detects an exploit or extreme variance, the Event Sentinel immediately emits a PAUSE and halts the vault.",
    animation: "fadeUp" as const,
    icon: (
      <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
      </svg>
    ),
  },
  {
    tag: "CCIP",
    title: "Cross-Chain Routing",
    body: "Seamless cross-chain liquidity paths, routing tokens securely across the Hub & Spoke network via Chainlink CCIP.",
    animation: "fadeUp" as const,
    icon: (
      <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
      </svg>
    ),
  },
];

const terminalLines = [
  { time: "16:04:12", text: "INIT: CRE Risk Scanner [v2.4]", color: "" },
  { time: "16:04:13", text: "TELEMETRY: Pulling DefiLlama TVL data...", color: "" },
  { time: "16:04:15", text: "OK: TVL variance nominal (0.012%)", color: "" },
  { time: "16:04:18", text: "AI_INFERENCE: Evaluating market sentiment...", color: "" },
  { time: "16:04:20", text: "FEED_CHK: var=0.037% score=9", color: "text-[#00FFB2]" },
  { time: "16:04:22", text: "SENTINEL: Vault remains unpaused.", color: "" },
];

const howItWorks = [
  {
    step: "01",
    title: "Deposit WETH",
    description: "Connect your wallet and deposit WETH into the autonomous vault. You receive oszWETH shares instantly.",
    icon: (
      <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 4v16m8-8H4" />
      </svg>
    ),
  },
  {
    step: "02",
    title: "AI Monitors Risk",
    description: "CRE workflows scan every 30s. AI evaluates protocol health, market signals, and stETH ratios in real time.",
    icon: (
      <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
      </svg>
    ),
  },
  {
    step: "03",
    title: "Earn Autonomous Yield",
    description: "Lido staking generates yield while Uniswap V3 hedges exposure. Fully autonomous, fully on-chain.",
    icon: (
      <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
      </svg>
    ),
  },
];

const tickerItems = [
  { label: "Protocol TVL", value: "12.84 WETH" },
  { label: "Target APY", value: "6.42%" },
  { label: "Risk Score", value: "12/100" },
  { label: "Last Scan", value: "4s ago" },
  { label: "Total Deposits", value: "847" },
  { label: "Uptime", value: "99.97%" },
  { label: "Networks", value: "3 chains" },
];

function Logo() {
  return (
    <div className="flex items-center gap-2.5">
      <div className="grid size-8 place-items-center rounded-lg bg-[rgba(0,255,178,0.1)] border border-[rgba(0,255,178,0.2)]">
        <svg viewBox="0 0 24 24" className="size-4 text-[#00FFB2]" fill="none">
          <path d="M4 12L12 4l3 3-5 5 5 5-3 3-8-8z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M14 4l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
      <span className="text-sm font-bold tracking-[0.15em] uppercase text-[#EBEBEF]">OSZILLOR</span>
    </div>
  );
}

export default function Home() {
  return (
    <main className="min-h-screen hero-bg">
      {/* ── Nav ─────────────────────────────────────────── */}
      <nav className="border-b border-[rgba(255,255,255,0.04)] glass">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 flex h-16 items-center justify-between">
          <Logo />
          <div className="hidden md:flex items-center gap-8 text-sm font-medium text-[#8B8B93]">
            <a href="#how-it-works" className="nav-link hover:text-[#EBEBEF] transition">How It Works</a>
            <a href="#brain" className="nav-link hover:text-[#EBEBEF] transition">The Brain</a>
            <a href="#features" className="nav-link hover:text-[#EBEBEF] transition">Capabilities</a>
            <a href="#security" className="nav-link hover:text-[#EBEBEF] transition">Security</a>
          </div>
          <div className="flex items-center gap-3">
            <Link href="/dashboard" className="btn-ghost !py-2.5 !px-5 text-sm hidden sm:inline-flex">
              Launch App
            </Link>
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
              connectButton={{ label: "Connect", className: "!rounded-lg !text-sm" }}
            />
          </div>
        </div>
      </nav>

      {/* ── Hero ────────────────────────────────────────── */}
      <section className="relative overflow-hidden">
        {/* Parallax ambient glows */}
        <ParallaxSection speed={0.2} className="absolute inset-0 pointer-events-none">
          <div className="absolute top-20 left-1/4 w-[600px] h-[600px] rounded-full bg-[rgba(0,255,178,0.04)] blur-[150px]" />
        </ParallaxSection>
        <ParallaxSection speed={0.4} className="absolute inset-0 pointer-events-none">
          <div className="absolute top-40 right-1/4 w-[400px] h-[400px] rounded-full bg-[rgba(59,130,246,0.03)] blur-[120px]" />
        </ParallaxSection>

        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 pt-28 pb-24 sm:pt-40 sm:pb-32 relative z-10">
          <div className="flex flex-col items-center text-center">
            <AnimateOnScroll animation="fadeUp" delay={0}>
              <div className="badge badge-mint mb-8">
                <div className="w-1.5 h-1.5 rounded-full bg-[#00FFB2] animate-pulse" />
                Powered by Chainlink CRE
              </div>
            </AnimateOnScroll>

            <AnimateOnScroll animation="fadeUp" delay={0.1}>
              <h1 className="max-w-4xl text-5xl sm:text-6xl lg:text-7xl font-black leading-[1.05] text-[#EBEBEF]">
                DeFi That Thinks{" "}
                <br className="hidden sm:block" />
                <span className="text-gradient">for Itself.</span>
              </h1>
            </AnimateOnScroll>

            <AnimateOnScroll animation="fadeUp" delay={0.2}>
              <p className="mt-6 max-w-2xl text-lg sm:text-xl text-[#8B8B93] leading-relaxed">
                The first autonomous, risk-managed yield protocol powered by the
                Chainlink Runtime Environment and embedded AI intelligence.
              </p>
            </AnimateOnScroll>

            <AnimateOnScroll animation="fadeUp" delay={0.3}>
              <div className="mt-10 flex flex-wrap justify-center gap-4">
                <Link href="/dashboard" className="btn-mint">
                  Launch App
                </Link>
                <a href="#brain" className="btn-ghost">
                  Read the Specs
                </a>
              </div>
            </AnimateOnScroll>

            {/* Quick stats with CountUp */}
            <AnimateOnScroll animation="fadeUp" delay={0.4}>
              <div className="mt-16 flex items-center gap-8 sm:gap-12">
                <div className="text-center">
                  <p className="text-2xl sm:text-3xl font-black font-mono text-[#EBEBEF]">
                    <CountUp end={30} suffix="s" className="tabular-nums" />
                  </p>
                  <p className="stat-label mt-1">Scan Interval</p>
                </div>
                <div className="text-center">
                  <p className="text-2xl sm:text-3xl font-black font-mono text-[#EBEBEF]">
                    <CountUp end={6.42} decimals={2} suffix="%" className="tabular-nums" />
                  </p>
                  <p className="stat-label mt-1">Target APY</p>
                </div>
                <div className="text-center">
                  <p className="text-2xl sm:text-3xl font-black font-mono text-[#EBEBEF]">
                    <CountUp end={100} suffix="%" className="tabular-nums" />
                  </p>
                  <p className="stat-label mt-1">Autonomous</p>
                </div>
              </div>
            </AnimateOnScroll>
          </div>
        </div>
      </section>

      {/* ── How It Works ──────────────────────────────── */}
      <section id="how-it-works" className="px-4 sm:px-6 lg:px-8 py-28">
        <div className="mx-auto max-w-7xl">
          <AnimateOnScroll animation="fadeUp">
            <div className="text-center mb-16">
              <p className="stat-label text-[#00FFB2] mb-3">Simple Process</p>
              <h2 className="text-3xl sm:text-4xl lg:text-5xl font-bold tracking-tight">How It Works</h2>
            </div>
          </AnimateOnScroll>

          <div className="grid gap-8 sm:grid-cols-3 relative">
            {/* Connector lines (desktop only) */}
            <div className="hidden sm:block absolute top-16 left-[20%] right-[20%] h-px border-t-2 border-dashed border-[#232326]" />

            {howItWorks.map((step, i) => (
              <AnimateOnScroll key={step.step} animation="fadeUp" delay={i * 0.15}>
                <div className="glass-card p-8 text-center relative hover-lift">
                  <div className="w-14 h-14 rounded-2xl bg-[rgba(0,255,178,0.08)] border border-[rgba(0,255,178,0.15)] flex items-center justify-center mx-auto mb-6 text-[#00FFB2]">
                    {step.icon}
                  </div>
                  <div className="text-[10px] font-bold tracking-[0.2em] text-[#56565E] uppercase mb-2">Step {step.step}</div>
                  <h3 className="text-xl font-bold mb-3">{step.title}</h3>
                  <p className="text-sm text-[#8B8B93] leading-relaxed">{step.description}</p>
                </div>
              </AnimateOnScroll>
            ))}
          </div>
        </div>
      </section>

      {/* ── The Brain ───────────────────────────────────── */}
      <section id="brain" className="px-4 sm:px-6 lg:px-8 py-28">
        <div className="mx-auto max-w-7xl">
          <AnimateOnScroll animation="fadeUp">
            <div className="card-glow p-8 sm:p-12 lg:p-16 grid gap-12 lg:grid-cols-[1fr_1fr] items-center relative overflow-hidden">
              {/* Glow */}
              <div className="absolute -right-20 top-0 w-[400px] h-[400px] bg-[rgba(0,255,178,0.04)] rounded-full blur-[100px] pointer-events-none" />

              <div className="relative z-10">
                <p className="stat-label text-[#00FFB2] mb-4">Continuous Risk Intelligence</p>
                <h2 className="text-3xl sm:text-4xl lg:text-5xl font-bold tracking-tight mb-6">The AI Gatekeeper</h2>
                <p className="text-[#8B8B93] leading-relaxed mb-4">
                  Our Chainlink CRE workflows execute every 30 seconds, pulling live off-chain telemetry
                  from DefiLlama, news aggregators, and CoinGecko.
                </p>
                <p className="text-[#8B8B93] leading-relaxed mb-8">
                  This data feeds into local AI models that evaluate protocol health. If an anomaly is
                  detected, the Event Sentinel instantly emits a PAUSE to protect liquidity.
                </p>

                <div className="flex items-center gap-6 border-t border-[#232326] pt-6">
                  <div>
                    <span className="text-2xl font-mono font-bold text-[#EBEBEF]">30s</span>
                    <p className="stat-label mt-1">Scan Interval</p>
                  </div>
                  <div className="h-10 w-px bg-[#232326]" />
                  <div>
                    <span className="text-2xl font-mono font-bold text-[#00FFB2]">100%</span>
                    <p className="stat-label mt-1">Autonomous</p>
                  </div>
                </div>
              </div>

              {/* Terminal */}
              <div className="terminal relative z-10">
                <div className="terminal-header">
                  <div className="terminal-dots">
                    <span className="bg-[#FF3B5C]" />
                    <span className="bg-[#FFB020]" />
                    <span className="bg-[#00FFB2]" />
                  </div>
                  <p className="text-[10px] font-mono tracking-[0.2em] text-[#00FFB2]/60 uppercase">CRE//RISK_TERM</p>
                </div>
                <div className="terminal-body relative min-h-[300px]">
                  <div className="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-[#050507] to-transparent z-10 pointer-events-none" />
                  <div className="space-y-1">
                    {terminalLines.map((line, i) => (
                      <p key={i} className="opacity-0 animate-fade-in-up" style={{ animationDelay: `${0.3 + i * 0.15}s`, animationFillMode: "forwards" }}>
                        <span className="text-[#56565E]">[{line.time}]</span>{" "}
                        <span className={line.color}>{line.text}</span>
                        {line.color && <span className="text-[#00FFB2] ml-1">[SAFE]</span>}
                      </p>
                    ))}
                    <div className="flex items-center gap-2 mt-4 pt-2">
                      <span className="text-[#00FFB2]">root@CRE:~#</span>
                      <span className="w-2 h-4 bg-[#00FFB2]/70 animate-pulse" />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </AnimateOnScroll>
        </div>
      </section>

      {/* ── Features ────────────────────────────────────── */}
      <section id="features" className="px-4 sm:px-6 lg:px-8 py-28">
        <div className="mx-auto max-w-7xl">
          <AnimateOnScroll animation="fadeUp">
            <div className="text-center mb-14">
              <h2 className="text-3xl sm:text-4xl font-bold tracking-tight">Protocol Capabilities</h2>
              <p className="mt-4 text-[#8B8B93] max-w-xl mx-auto">
                Engineered for institutional security and fully autonomous yield generation.
              </p>
            </div>
          </AnimateOnScroll>

          <div className="grid gap-6 sm:grid-cols-3">
            {features.map((feat, i) => (
              <AnimateOnScroll key={feat.title} animation={feat.animation} delay={i * 0.1}>
                <article className="glass-card feature-card p-8 group relative overflow-hidden">
                  <div className="absolute -right-8 -bottom-8 w-32 h-32 rounded-full bg-[rgba(0,255,178,0.03)] blur-2xl group-hover:bg-[rgba(0,255,178,0.1)] transition-all duration-700" />

                  <div className="relative z-10">
                    <div className="flex items-center gap-3 mb-6">
                      <div className="grid size-10 place-items-center rounded-lg bg-[rgba(0,255,178,0.08)] text-[#00FFB2] border border-[rgba(0,255,178,0.15)]">
                        {feat.icon}
                      </div>
                      <span className="badge badge-mint text-[10px]">{feat.tag}</span>
                    </div>
                    <h3 className="text-xl font-bold mb-3">{feat.title}</h3>
                    <p className="text-sm text-[#8B8B93] leading-relaxed">{feat.body}</p>
                  </div>
                </article>
              </AnimateOnScroll>
            ))}
          </div>
        </div>
      </section>

      {/* ── Live Protocol Metrics Ticker ────────────────── */}
      <section className="border-y border-[#232326] py-5 overflow-hidden">
        <div className="marquee-track">
          {[...tickerItems, ...tickerItems].map((item, i) => (
            <div key={i} className="flex items-center gap-3 px-8 shrink-0">
              <span className="text-[10px] font-bold tracking-[0.15em] uppercase text-[#56565E]">{item.label}</span>
              <span className="text-sm font-bold font-mono text-[#EBEBEF]">{item.value}</span>
              <div className="w-1 h-1 rounded-full bg-[#232326]" />
            </div>
          ))}
        </div>
      </section>

      {/* ── Security ────────────────────────────────────── */}
      <section id="security" className="px-4 sm:px-6 lg:px-8 py-28">
        <div className="mx-auto max-w-7xl">
          <AnimateOnScroll animation="fadeUp">
            <div className="glass-card p-12 sm:p-16 text-center relative overflow-hidden">
              <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(0,255,178,0.04),transparent_60%)] pointer-events-none" />

              <div className="relative z-10">
                <div className="flex justify-center gap-3 mb-8">
                  <div className="badge badge-mint">
                    <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                    </svg>
                    Audited
                  </div>
                  <div className="badge badge-mint">
                    <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
                    </svg>
                    Open Source
                  </div>
                </div>

                <h2 className="text-3xl sm:text-4xl font-bold tracking-tight mb-4">Uncompromising Security</h2>
                <p className="max-w-xl mx-auto text-[#8B8B93] leading-relaxed mb-10">
                  Structurally mitigated against 17 critical vulnerabilities identified by Trail of Bits.
                  Built rigorously on Foundry with 290+ tests and full coverage.
                </p>

                <div className="flex justify-center gap-8 sm:gap-12 items-center border-t border-[#232326] pt-8 max-w-2xl mx-auto">
                  {[
                    { label: "Partner", value: "Chainlink BUILD" },
                    { label: "Tested", value: "Foundry" },
                    { label: "Live Testnet", value: "Sepolia" },
                  ].map((item, i) => (
                    <div key={item.label} className="flex items-center gap-8">
                      <div className="text-center">
                        <p className="text-base font-bold font-mono text-[#EBEBEF]">{item.value}</p>
                        <p className="stat-label mt-1">{item.label}</p>
                      </div>
                      {i < 2 && <div className="w-px h-8 bg-[#232326]" />}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </AnimateOnScroll>
        </div>
      </section>

      {/* ── Footer ──────────────────────────────────────── */}
      <footer className="border-t border-[#232326] mt-12">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-12">
          <div className="grid gap-8 lg:grid-cols-[1fr_1fr] items-start">
            <div>
              <Logo />
              <p className="mt-4 max-w-sm text-sm text-[#56565E] leading-relaxed">
                OSZILLOR is an experimental decentralized yield protocol operating on the Sepolia Testnet.
                Interact at your own risk.
              </p>
            </div>
            <div className="grid grid-cols-2 gap-6 text-sm lg:justify-items-end">
              <div className="space-y-3">
                <p className="stat-label mb-4">Resources</p>
                <a href="#" className="block text-[#56565E] hover:text-[#EBEBEF] transition">Documentation</a>
                <a href="#" className="block text-[#56565E] hover:text-[#EBEBEF] transition">GitHub Repo</a>
                <a href="#" className="block text-[#56565E] hover:text-[#EBEBEF] transition">Smart Contracts</a>
              </div>
              <div className="space-y-3 lg:text-right">
                <p className="stat-label mb-4">Community</p>
                <a href="#" className="block text-[#56565E] hover:text-[#EBEBEF] transition">Twitter / X</a>
                <a href="#" className="block text-[#56565E] hover:text-[#EBEBEF] transition">Discord</a>
              </div>
            </div>
          </div>
          <div className="mt-12 text-center text-[10px] text-[#56565E]/60 uppercase tracking-[0.2em]">
            &copy; 2026 OSZILLOR Protocol. All rights reserved.
          </div>
        </div>
      </footer>
    </main>
  );
}
