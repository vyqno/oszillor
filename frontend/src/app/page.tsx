import Link from "next/link";

const valueCards = [
  {
    title: "Atomic Fund Routing",
    body: "Yield generation begins in the same block. Instant, capital-efficient deployment through optimized strategies.",
    tag: "Instant",
  },
  {
    title: "Hardened Panic Circuit",
    body: "If the AI detects an exploit or extreme variance, the Event Sentinel immediately emits a PAUSE and halts the vault.",
    tag: "Secure",
  },
  {
    title: "CCIP Ready Routing",
    body: "Seamless cross-chain liquidity paths, routing tokens securely across the Hub & Spoke network.",
    tag: "Cross-chain",
  },
];

const news = [
  { title: "CRE Risk Scanner publishes confidence ranges", date: "March 07, 2026" },
  { title: "Hub deployment validation completed on Sepolia", date: "March 01, 2026" },
  { title: "All 17 Trail of Bits security fixes implemented", date: "February 28, 2026" },
];

function Logo() {
  return (
    <div className="flex items-center gap-2">
      <div className="grid size-9 place-items-center rounded-2xl bg-[#2563eb]/20 ring-1 ring-white/30">
        <svg viewBox="0 0 24 24" className="size-4 text-[#7fa8ff]" fill="none">
          <path d="M4 12L12 4l3 3-5 5 5 5-3 3-8-8z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M14 4l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
      <div className="text-sm font-semibold tracking-tight text-white uppercase tracking-widest">OSZILLOR</div>
    </div>
  );
}

export default function Home() {
  return (
    <main className="pb-16 bg-[#030B1A] min-h-screen text-white/80 selection:bg-[#2563eb]/30">
      
      {/* SECTION 1: The Hero */}
      <section className="px-4 pb-8 pt-6 sm:px-8 lg:px-12">
        <div className="hero-panel relative mx-auto max-w-6xl overflow-hidden rounded-[30px] px-5 pb-16 pt-5 text-white sm:px-8 sm:pt-7 lg:px-12 border border-white/5">
          {/* Background Ambient Glows */}
          <div className="absolute -right-8 top-20 h-[500px] w-[500px] rounded-full bg-[#1D4ED8]/20 blur-[120px] pointer-events-none" />
          <div className="absolute -left-20 top-40 h-[400px] w-[400px] rounded-full bg-[#2563EB]/10 blur-[100px] pointer-events-none" />

          {/* Nav */}
          <div className="flex items-center justify-between relative z-10">
            <Logo />
            <div className="hidden items-center gap-8 text-sm font-medium text-white/60 md:flex">
              <a href="#brain" className="hover:text-white transition">The Brain</a>
              <a href="#features" className="hover:text-white transition">Capabilities</a>
              <a href="#security" className="hover:text-white transition">Security</a>
            </div>
            <Link href="/dashboard" className="pill border border-[#2563eb]/30 bg-[#2563eb]/10 hover:bg-[#2563eb]/20 px-5 py-2.5 text-xs font-bold text-[#7fa8ff] transition shadow-[0_0_15px_rgba(37,99,235,0.2)]">
              Launch App
            </Link>
          </div>

          <div className="mt-20 flex flex-col items-center text-center relative z-10 mb-10">
            <p className="pill inline-flex border border-[#2563eb]/30 bg-[#2563eb]/10 px-4 py-1.5 text-xs font-mono text-[#7fa8ff] tracking-widest uppercase mb-6">
              Powered by Chainlink CRE
            </p>
            <h1 className="max-w-4xl text-5xl font-extrabold leading-[1.1] tracking-[-0.02em] sm:text-6xl lg:text-7xl text-white">
              DeFi That Thinks <br/><span className="text-transparent bg-clip-text bg-gradient-to-r from-[#7fa8ff] to-[#2563eb]">for Itself.</span>
            </h1>
            <p className="mt-6 max-w-2xl text-lg text-white/60 sm:text-xl font-light">
              The first autonomous, risk-managed yield protocol powered by the Chainlink Runtime Environment and embedded AI Intelligence.
            </p>
            <div className="mt-10 flex flex-wrap justify-center gap-4">
              <Link href="/dashboard" className="btn-primary px-8 py-4 text-base font-bold text-white transition shadow-[0_0_30px_rgba(37,99,235,0.4)]">
                Launch App
              </Link>
              <a href="#brain" className="pill border border-white/20 bg-white/5 hover:bg-white/10 px-8 py-4 text-base font-semibold text-white transition">
                Read the Specs
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* SECTION 2: "The Brain" */}
      <section id="brain" className="px-4 py-12 sm:px-8 lg:px-12">
        <div className="dark-band mx-auto grid max-w-6xl gap-12 overflow-hidden rounded-[30px] px-8 py-16 text-white sm:px-12 lg:grid-cols-[1fr_1fr] items-center border border-white/5 shadow-[0_20px_50px_rgba(0,0,0,0.5)] relative">
          
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(37,99,235,0.1),transparent_50%)] pointer-events-none" />

          <div className="relative z-10">
            <p className="text-[11px] font-mono uppercase tracking-[0.22em] text-[#7fa8ff] mb-4">Continuous Risk Intelligence</p>
            <h2 className="text-4xl font-bold sm:text-5xl tracking-tight mb-6">The AI Gatekeeper</h2>
            <p className="text-base text-white/60 leading-relaxed mb-6">
              Our Chainlink CRE workflows execute every 30 seconds, pulling live off-chain telemetry from DefiLlama, News, and CoinGecko.
            </p>
            <p className="text-base text-white/60 leading-relaxed mb-8">
              This data feeds into local AI models that evaluate protocol health. If an anomaly is detected, the Event Sentinel instantly emits a PAUSE to protect liquidity.
            </p>
            <div className="flex items-center gap-4 border-t border-white/10 pt-6">
               <div className="flex flex-col">
                  <span className="text-2xl font-mono font-bold text-white">30s</span>
                  <span className="text-[10px] uppercase tracking-widest text-white/40">Scan Interval</span>
               </div>
               <div className="h-10 w-px bg-white/10" />
               <div className="flex flex-col">
                  <span className="text-2xl font-mono font-bold text-[#10b981]">100%</span>
                  <span className="text-[10px] uppercase tracking-widest text-white/40">Autonomous</span>
               </div>
            </div>
          </div>

          {/* Terminal Mock */}
          <div className="bg-[#050b14] border border-[#2563eb]/20 rounded-[20px] h-[350px] flex flex-col overflow-hidden shadow-[inset_0_4px_30px_rgba(0,0,0,0.5)] relative z-10">
            <div className="bg-[#0a1122] border-b border-white/5 px-4 py-3 flex items-center justify-between">
                <div className="flex gap-1.5">
                  <div className="w-2.5 h-2.5 rounded-full bg-[#ef4444]" />
                  <div className="w-2.5 h-2.5 rounded-full bg-[#f59e0b]" />
                  <div className="w-2.5 h-2.5 rounded-full bg-[#10b981]" />
                </div>
                <p className="text-[10px] font-mono tracking-widest text-[#7fa8ff]/80">CRE//RISK_TERM</p>
            </div>
            <div className="p-5 font-mono text-xs leading-loose text-[#7fa8ff]/90 flex-1 relative overflow-hidden">
              <div className="absolute inset-0 bg-gradient-to-b from-transparent to-[#050b14] z-10 pointer-events-none" />
              <div className="space-y-2 opacity-90 animate-fade-in-up">
                <p><span className="text-white/30">[16:04:12]</span> INIT: CRE Risk Scanner [v2.4]</p>
                <p><span className="text-white/30">[16:04:13]</span> TELEMETRY: Pulling DefiLlama TVL data...</p>
                <p><span className="text-white/30">[16:04:15]</span> OK: TVL variance nominal (0.012%)</p>
                <p><span className="text-white/30">[16:04:18]</span> AI_INFERENCE: Evaluating market sentiment...</p>
                <p><span className="text-white/30">[16:04:20]</span> FEED_CHK: var=0.037% score=9 <span className="text-emerald-400">[SAFE]</span></p>
                <p><span className="text-white/30">[16:04:22]</span> SENTINEL: Vault remains unpaused.</p>
                <div className="flex items-center gap-2 mt-4">
                    <span className="text-emerald-400">root@CRE:~#</span>
                    <span className="w-1.5 h-3 bg-white/70 animate-pulse" />
                </div>
              </div>
            </div>
          </div>

        </div>
      </section>

      {/* SECTION 3: Value Props */}
      <section id="features" className="mx-auto max-w-6xl px-4 py-16 sm:px-8 lg:px-12">
        <div className="text-center mb-12">
           <h2 className="text-3xl font-bold text-white sm:text-4xl tracking-tight">Protocol Capabilities</h2>
           <p className="mt-4 text-base text-white/50 max-w-xl mx-auto">
             Engineered for institutional security and fully autonomous yield generation.
           </p>
        </div>

        <div className="grid gap-6 sm:grid-cols-3">
          {valueCards.map((card) => (
            <article key={card.title} className="glass-card rounded-[24px] p-8 border border-white/5 hover:border-white/10 transition-colors relative overflow-hidden group">
              <div className="absolute -right-10 -bottom-10 h-32 w-32 rounded-full bg-[#2563eb]/10 blur-3xl group-hover:bg-[#2563eb]/20 transition-all duration-700" />
              <p className="pill inline-flex border border-[#2563eb]/30 bg-[#2563eb]/10 px-3 py-1 text-[10px] font-mono tracking-widest text-[#7fa8ff] uppercase mb-6">{card.tag}</p>
              <h3 className="text-xl font-bold text-white mb-3 tracking-snug">{card.title}</h3>
              <p className="text-sm leading-relaxed text-white/60">{card.body}</p>
            </article>
          ))}
        </div>
      </section>

      {/* SECTION 4: Developer / Trust */}
      <section id="security" className="px-4 py-12 sm:px-8 lg:px-12">
        <div className="hero-panel relative mx-auto max-w-6xl overflow-hidden rounded-[30px] px-8 py-16 text-center sm:px-12 border border-white/5">
           <div className="absolute inset-0 bg-[#1D4ED8]/5" />
           
           <div className="relative z-10 flex flex-col items-center">
             <div className="flex gap-4 mb-8">
                <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-white/5 border border-white/10">
                   <svg className="w-4 h-4 text-[#7fa8ff]" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" /></svg>
                   <span className="text-xs font-semibold text-white/80 uppercase tracking-widest">Audited</span>
                </div>
                <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-white/5 border border-white/10">
                   <svg className="w-4 h-4 text-[#7fa8ff]" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" /></svg>
                   <span className="text-xs font-semibold text-white/80 uppercase tracking-widest">Open Source</span>
                </div>
             </div>

             <h2 className="text-3xl font-bold sm:text-4xl text-white tracking-tight mb-4">Uncompromising Security</h2>
             <p className="max-w-xl text-base text-white/60 mb-8 leading-relaxed">
               Structurally mitigated against 17 critical vulnerabilities identified by Trail of Bits. Built rigorously on Foundry with full coverage.
             </p>
             
             <div className="flex justify-center gap-8 items-center border-t border-white/10 pt-8 w-full max-w-2xl">
                <div className="text-center opacity-60">
                   <p className="text-lg font-bold font-mono text-white">Chainlink BUILD</p>
                   <p className="text-[10px] uppercase tracking-widest mt-1">Partner</p>
                </div>
                <div className="w-px h-8 bg-white/10" />
                <div className="text-center opacity-60">
                   <p className="text-lg font-bold font-mono text-white">Foundry</p>
                   <p className="text-[10px] uppercase tracking-widest mt-1">Tested</p>
                </div>
                <div className="w-px h-8 bg-white/10" />
                <div className="text-center opacity-60">
                   <p className="text-lg font-bold font-mono text-white">Sepolia</p>
                   <p className="text-[10px] uppercase tracking-widest mt-1">Live Testnet</p>
                </div>
             </div>
           </div>
        </div>
      </section>

      {/* SECTION 5: Footer */}
      <footer className="px-4 pt-10 pb-4 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl border-t border-white/10 pt-10">
          <div className="grid gap-8 lg:grid-cols-[1fr_1fr] items-start">
            <div>
              <Logo />
              <p className="mt-4 max-w-sm text-sm text-white/40 leading-relaxed">
                OSZILLOR is an experimental decentralized yield protocol operating on the Sepolia Testnet. Interact at your own risk.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-6 text-sm lg:justify-items-end">
              <div className="space-y-3">
                <p className="font-semibold text-white/80 mb-4 uppercase tracking-widest text-[11px]">Resources</p>
                <a href="#" className="block text-white/40 hover:text-white transition">Documentation</a>
                <a href="#" className="block text-white/40 hover:text-white transition">GitHub Repo</a>
                <a href="#" className="block text-white/40 hover:text-white transition">Smart Contracts</a>
              </div>
              <div className="space-y-3 lg:text-right">
                <p className="font-semibold text-white/80 mb-4 uppercase tracking-widest text-[11px]">Community</p>
                <a href="#" className="block text-white/40 hover:text-white transition">Twitter / X</a>
                <a href="#" className="block text-white/40 hover:text-white transition">Discord</a>
              </div>
            </div>
          </div>
          <div className="mt-16 text-center text-[10px] text-white/30 uppercase tracking-widest">
             © 2026 OSZILLOR Protocol. All rights reserved.
          </div>
        </div>
      </footer>
    </main>
  );
}
