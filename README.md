# 🌊 OSZILLOR

<p align="center">
  <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=24&pause=1000&color=375BD2&center=true&vCenter=true&width=800&lines=Risk-managed+ETH+yield+vault;Autonomous+AI-driven+incident+response;Powered+by+Chainlink+CRE%2C+CCIP%2C+and+Price+Feeds" alt="Typing SVG" />
</p>

[![Base](https://img.shields.io/badge/Network-Base_Sepolia-0052FF?style=for-the-badge&logo=coinbase&logoColor=white)](https://sepolia.basescan.org/)
[![Ethereum](https://img.shields.io/badge/Network-Ethereum_Sepolia-627EEA?style=for-the-badge&logo=ethereum&logoColor=white)](https://sepolia.etherscan.io/)
[![Chainlink](https://img.shields.io/badge/Powered_by-Chainlink-375BD2?style=for-the-badge&logo=chainlink&logoColor=white)](https://chain.link/)
[![Next.js](https://img.shields.io/badge/Frontend-Next.js-black?style=for-the-badge&logo=next.js&logoColor=white)](https://nextjs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![X (Twitter)](https://img.shields.io/badge/X-vyqno-black?style=for-the-badge&logo=x&logoColor=white)](https://x.com/vyqno)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0xhitesh-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://linkedin.com/in/0xhitesh)

> **Risk-managed ETH yield vault with autonomous AI-driven incident response, powered by Chainlink CRE, CCIP, and Price Feeds.**

Users deposit ETH to earn Lido staking yield. When markets crash, the protocol detects the threat via AI, pauses itself, and rescues funds — without human intervention.

> **Live UI**: [oszillor.replit.app](https://oszillor.replit.app) | **Source Code**: [github.com/vyqno/oszillor](https://github.com/vyqno/oszillor)
> **Networks**: Base Sepolia + Ethereum Sepolia | **Demo**: [`demo/e2e-master.sh`](./demo/e2e-master.sh)

## 📖 Table of Contents

- [📖 Overview](#-overview)
- [🏗️ System Architecture](#-system-architecture)
- [📥 How a Deposit Works](#-how-a-deposit-works)
- [📤 How a Withdraw Works](#-how-a-withdraw-works)
- [🤖 Autonomous Risk Pipeline](#-autonomous-risk-pipeline)
- [🏗️ Contracts](#-contracts)
  - [OszillorVault](#oszillorvault)
  - [VaultStrategy](#vaultstrategy)
  - [OszillorToken](#oszillortoken)
  - [RiskEngine](#riskengine)
  - [EventSentinel](#eventsentinel)
  - [RebaseExecutor](#rebaseexecutor)
  - [OszillorTokenPool](#oszillortokenpool)
  - [HubPeer and SpokePeer](#hubpeer-and-spokepeer)
  - [Libraries](#libraries)
- [⚙️ CRE Workflows](#-cre-workflows)
  - [W1 — Risk Scanner](#w1--risk-scanner)
  - [W2 — Event Sentinel](#w2--event-sentinel)
  - [W3 — Rebase Executor](#w3--rebase-executor)
  - [CRE Capability Matrix](#cre-capability-matrix)
- [💰 x402 Risk Intelligence API](#-x402-risk-intelligence-api)
  - [W4 — Risk Alerts](#w4--risk-alerts)
  - [API Endpoints](#api-endpoints)
  - [AI Agent (Coinbase AgentKit)](#ai-agent-coinbase-agentkit)
- [🧠 AI Integration](#-ai-integration)
- [🔒 Privacy Integration](#-privacy-integration)
- [🌉 Cross-Chain Architecture (CCIP)](#-cross-chain-architecture-ccip)
- [🚦 Risk State Machine](#-risk-state-machine)
- [⚖️ Rebalance Logic](#-rebalance-logic)
- [🧪 Testing](#-testing)
- [🛡️ Formal Verification](#-formal-verification)
- [🕵️ Security Audit](#-security-audit)
- [🌐 Testnet Deployment](#-testnet-deployment)
- [🎬 E2E Demo](#-e2e-demo)
- [🔗 Chainlink File References](#-chainlink-file-references)
- [💻 Local Development](#-local-development)
- [🖥️ Frontend](#-frontend)
- [🗺️ Repository Map](#-repository-map)
- [⚠️ Known Issues](#-known-issues)
- [🚀 Future Developments](#-future-developments)
- [🧗 Challenges](#-challenges)

## 📖 Overview

**Problem**: DeFi yield protocols are vulnerable to exploits, depegs, and market crashes. By the time a human notices and acts, funds are already gone.

**Solution**: OSZILLOR removes the human from the loop. Three coordinated CRE workflows continuously monitor the market, reason about threats using an LLM, reach DON consensus, and autonomously execute protective actions on-chain.

```
                          OSZILLOR SYSTEM OVERVIEW

  ┌─────────────────────────────────────────────────────────────────┐
  │                     CHAINLINK DON (CRE)                         │
  │                                                                 │
  │  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐     │
  │  │  W1 Risk     │  │  W2 Event    │  │  W3 Rebase        │     │
  │  │  Scanner     │  │  Sentinel    │  │  Executor         │     │
  │  │  (30s cron)  │  │  (15s cron)  │  │  (5m cron)        │     │
  │  └──────┬───────┘  └──────┬───────┘  └────────┬──────────┘     │
  │         │                 │                    │                │
  │    ┌────┴────┐       ┌────┴────┐          ┌────┴────┐          │
  │    │CoinGecko│       │CoinGecko│          │EVM Read │          │
  │    │DeFiLlama│       └─────────┘          │Compute  │          │
  │    │News API │                            └─────────┘          │
  │    │Groq LLM │                                                 │
  │    └─────────┘                                                 │
  └─────────┬─────────────────┬────────────────────┬───────────────┘
            │ EVM Write       │ EVM Write          │ EVM Write
            ▼                 ▼                    ▼
  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐
  │  RiskEngine  │  │EventSentinel │  │ RebaseExecutor    │
  │  (risk score │  │  (emergency  │  │ (rebalance +      │
  │   + AI hash) │  │   pause)     │  │  rebase trigger)  │
  └──────┬───────┘  └──────┬───────┘  └────────┬──────────┘
         │                 │                    │
         └────────────┬────┴────────────────────┘
                      ▼
            ┌──────────────────┐        ┌──────────────────┐
            │  OszillorVault   │◄──────►│  VaultStrategy   │
            │  (user deposits/ │        │  (Lido staking,  │
            │   withdrawals)   │        │   Uniswap hedge, │
            └────────┬─────────┘        │   Chainlink feed)│
                     │                  └──────────────────┘
                     ▼
            ┌──────────────────┐
            │  OszillorToken   │
            │  (rebase share   │
            │   token — OSZ)   │
            └──────────────────┘
```

## 📥 How a Deposit Works

Deposits use "Atomic Fund Routing" — funds reach the yield strategy in the same transaction as the deposit. No idle capital.

```
  USER                  VAULT                STRATEGY              LIDO
   │                      │                     │                    │
   │  deposit(wethAmt)    │                     │                    │
   ├─────────────────────►│                     │                    │
   │                      │                     │                    │
   │  transferFrom(WETH)  │                     │                    │
   │◄─ ─ ─ ─ ─ ─ ─ ─ ─ ─┤                     │                    │
   │                      │                     │                    │
   │                      │  transfer(WETH)     │                    │
   │                      ├────────────────────►│                    │
   │                      │                     │                    │
   │                      │                     │  stakeInLido()     │
   │                      │                     ├───────────────────►│
   │                      │                     │                    │
   │                      │                     │  ◄─── stETH ──────┤
   │                      │                     │                    │
   │  ◄─── mint(OSZ) ────┤                     │                    │
   │                      │                     │                    │

   Result: User has OSZ tokens. WETH is staked in Lido earning yield.
           Zero idle capital in the vault.
```

## 📤 How a Withdraw Works

The vault automatically ensures liquidity by pulling funds back from the strategy if needed.

```
  USER                  VAULT                STRATEGY              LIDO
   │                      │                     │                    │
   │  withdraw(wethAmt)   │                     │                    │
   ├─────────────────────►│                     │                    │
   │                      │                     │                    │
   │                      │  _ensureLiquidity() │                    │
   │                      ├────────────────────►│                    │
   │                      │                     │                    │
   │                      │  [if insufficient   │  unstakeFromLido() │
   │                      │   idle WETH]        ├───────────────────►│
   │                      │                     │                    │
   │                      │                     │  ◄─── WETH ───────┤
   │                      │                     │                    │
   │                      │  ◄── WETH ─────────┤                    │
   │                      │                     │                    │
   │  ◄─── WETH ─────────┤                     │                    │
   │                      │                     │                    │
   │  ─── burn(OSZ) ─────►│                     │                    │
   │                      │                     │                    │

   Result: User receives WETH. OSZ tokens burned.
           Strategy unstakes from Lido only if necessary.
```

## 🤖 Autonomous Risk Pipeline

This is the core of OSZILLOR. Three CRE workflows coordinate through shared on-chain state to detect, confirm, and respond to threats — autonomously.

```
  ┌─────────────────────────── THREAT DETECTED ──────────────────────────┐
  │                                                                      │
  │  STEP 1: W1 Risk Scanner detects anomaly (every 30s)                 │
  │  ════════════════════════════════════════════                         │
  │                                                                      │
  │  CoinGecko ──► ETH price drop: -12%        ┐                        │
  │  CoinGecko ──► stETH/ETH ratio: 0.94       ├─► Risk Score: 85       │
  │  DeFiLlama ──► TVL dropping rapidly         │   (CRITICAL)           │
  │  News API ───► "Lido exploit confirmed"     │                        │
  │  Groq LLM ──► "FATAL — recommend pause"    ┘                        │
  │                       │                                              │
  │                       ▼                                              │
  │              ┌─────────────────┐                                     │
  │              │   DON Consensus │  Nodes agree: riskScore = 85        │
  │              └────────┬────────┘                                     │
  │                       │                                              │
  │                       ▼                                              │
  │              ┌─────────────────┐                                     │
  │              │   RiskEngine    │  State: CAUTION ──► CRITICAL        │
  │              │   (on-chain)    │  AI hash stored on-chain             │
  │              └─────────────────┘                                     │
  │                                                                      │
  │  STEP 2: W2 Event Sentinel confirms threat (every 15s)               │
  │  ══════════════════════════════════════════════════                   │
  │                                                                      │
  │  CoinGecko ──► Independent price check      ┐                       │
  │  Compute ────► Rapid drop confirmed          ├─► Threat: YES        │
  │  Compute ────► stETH depeg confirmed         ┘                      │
  │                       │                                              │
  │                       ▼                                              │
  │              ┌─────────────────┐                                     │
  │              │ EventSentinel   │  vault.pause()                      │
  │              │ (on-chain)      │  vault.setEmergencyMode(true)       │
  │              └─────────────────┘                                     │
  │                       │                                              │
  │                       ▼                                              │
  │              ╔═════════════════╗                                     │
  │              ║  VAULT PAUSED   ║  No deposits or withdrawals         │
  │              ╚═════════════════╝                                     │
  │                                                                      │
  │  STEP 3: W3 Rebase Executor rescues funds (every 5m)                 │
  │  ═══════════════════════════════════════════════════                  │
  │                                                                      │
  │  EVM Read ──► riskScore = 85 (CRITICAL)      ┐                      │
  │  EVM Read ──► strategy has 10 ETH staked      ├─► targetEthPct: 0%  │
  │  Compute ───► full withdrawal required        ┘   (all to USDC)     │
  │                       │                                              │
  │                       ▼                                              │
  │              ┌─────────────────┐                                     │
  │              │RebaseExecutor   │  vault.rebalance(0)                 │
  │              │(on-chain)       │    └─► strategy.emergencyWithdraw() │
  │              │                 │  vault.triggerRebase(factor)         │
  │              └─────────────────┘    └─► OSZ index updated            │
  │                                                                      │
  │  RESULT: Funds rescued. Vault paused. OSZ reflects new NAV.          │
  └──────────────────────────────────────────────────────────────────────┘
```

## 🏗️ Contracts

OSZILLOR uses a 6-layer modular architecture:

```
  ┌────────────────────────────────────────────────────────┐
  │  Layer 6: Adapters    OszillorTokenPool                │
  ├────────────────────────────────────────────────────────┤
  │  Layer 5: Peers       HubPeer, SpokePeer               │
  ├────────────────────────────────────────────────────────┤
  │  Layer 4: Core        OszillorVault, VaultStrategy,     │
  │                       OszillorToken                     │
  ├────────────────────────────────────────────────────────┤
  │  Layer 3: Modules     RiskEngine, EventSentinel,        │
  │                       RebaseExecutor, AlertRegistry,    │
  │                       CREReceiver, OszillorFees         │
  ├────────────────────────────────────────────────────────┤
  │  Layer 2: Interfaces  IOszillorVault, IVaultStrategy,   │
  │                       IRiskAdapter, IERC677Receiver     │
  ├────────────────────────────────────────────────────────┤
  │  Layer 1: Libraries   ShareMath, RiskMath,              │
  │                       CCIPOperations, DataStructures,   │
  │                       Roles, OszillorErrors             │
  └────────────────────────────────────────────────────────┘
```

### OszillorVault

[`src/core/OszillorVault.sol`](./contracts/src/core/OszillorVault.sol) — Main entry point. ERC-4626-style vault accepting WETH deposits, issuing OSZ share tokens. Implements atomic fund routing — deposits go directly to the strategy in the same tx.

Key functions:
- `deposit(uint256 assets)` — deposit WETH, route to strategy, mint OSZ
- `withdraw(uint256 assets)` — ensure liquidity, burn OSZ, return WETH
- `rebalance(uint256 targetEthPct)` — adjust ETH/USDC allocation (called by RebaseExecutor)
- `triggerRebase(int256 rebaseFactor)` — update OSZ token index based on NAV changes

### VaultStrategy

[`src/core/VaultStrategy.sol`](./contracts/src/core/VaultStrategy.sol) — Manages yield positions. Handles Lido staking (stETH), Uniswap V3 ETH↔USDC swaps for hedging, and Chainlink Price Feed for NAV calculation.

```
  VaultStrategy
  ┌─────────────────────────────────────────────────┐
  │                                                 │
  │  ┌───────────┐  ┌─────────────┐  ┌───────────┐ │
  │  │   Lido    │  │ Uniswap V3  │  │ Chainlink │ │
  │  │  staking  │  │  ETH/USDC   │  │  ETH/USD  │ │
  │  │  (yield)  │  │  (hedging)  │  │  (pricing) │ │
  │  └───────────┘  └─────────────┘  └───────────┘ │
  │                                                 │
  │  stakeInLido()      swapToUsdc()    getEthPrice()│
  │  unstakeFromLido()  swapToEth()     totalValueInEth()│
  │  emergencyWithdrawAll()                         │
  └─────────────────────────────────────────────────┘
```

- `totalValueInEth()` — returns total NAV (ETH balance + stETH balance + USDC converted via Chainlink feed)
- `emergencyWithdrawAll()` — unstakes all positions and returns everything to vault

### OszillorToken

[`src/core/OszillorToken.sol`](./contracts/src/core/OszillorToken.sol) — Rebase-capable ERC-20 share token. Uses an index-based system:

```
  balanceOf(user) = shares[user] × rebaseIndex
```

When vault NAV changes, `rebaseIndex` is adjusted — all holder balances update automatically without individual transfers. Implements ERC-677 `transferAndCall` for single-tx withdrawals. CCT-compatible for CCIP bridging.

### RiskEngine

[`src/modules/RiskEngine.sol`](./contracts/src/modules/RiskEngine.sol) — CRE receiver for W1. Receives risk reports via `KeystoneForwarder`. Validates reports with:

- Rate limiting (configurable cooldown between updates)
- Confidence threshold (rejects low-confidence scores)
- Delta clamping (score can't jump more than `maxDelta` per report)
- CRE 4-check validation (transmitter, signer, workflow ID, report format)

### EventSentinel

[`src/modules/EventSentinel.sol`](./contracts/src/modules/EventSentinel.sol) — CRE receiver for W2. Handles time-bounded emergency reports. Can pause the vault and trigger emergency mode. Reports expire after a configurable window to prevent stale replays.

### RebaseExecutor

[`src/modules/RebaseExecutor.sol`](./contracts/src/modules/RebaseExecutor.sol) — CRE receiver for W3. Receives rebalance reports (target ETH/USDC allocation + rebase factor). Calls `vault.rebalance()` then `vault.triggerRebase()`.

### OszillorTokenPool

[`src/adapters/OszillorTokenPool.sol`](./contracts/src/adapters/OszillorTokenPool.sol) — Share-based CCIP token pool for cross-chain OSZ bridging. Converts between rebased amounts and underlying shares during bridging to maintain correct balances across chains. Implements CCIP v1.5 struct-based interface (`Pool.LockOrBurnInV1`).

### HubPeer and SpokePeer

[`src/peers/HubPeer.sol`](./contracts/src/peers/HubPeer.sol), [`src/peers/SpokePeer.sol`](./contracts/src/peers/SpokePeer.sol) — CCIP peer contracts for cross-chain rebase propagation in a hub-spoke topology:

```
                    ┌─────────────┐
                    │   HubPeer   │
                    │(Base Sepolia│
                    └──┬──────┬───┘
              CCIP     │      │     CCIP
           ┌───────────┘      └───────────┐
           ▼                              ▼
  ┌─────────────────┐          ┌─────────────────┐
  │   SpokePeer     │          │   SpokePeer     │
  │  (Base Sepolia) │          │  (Avalanche)    │
  └─────────────────┘          └─────────────────┘

  Hub broadcasts: risk state, rebase index, share updates
  Spokes apply updates locally
```

### Libraries

| Library | Purpose | File |
| --- | --- | --- |
| `ShareMath` | Rebase index calculations, share ↔ amount conversions | [`ShareMath.sol`](./contracts/src/libraries/ShareMath.sol) |
| `RiskMath` | Risk score validation, state transitions, threshold constants | [`RiskMath.sol`](./contracts/src/libraries/RiskMath.sol) |
| `CCIPOperations` | CCIP message encoding/decoding, fee calculation | [`CCIPOperations.sol`](./contracts/src/libraries/CCIPOperations.sol) |
| `DataStructures` | Shared structs: RiskReport, RebalanceReport, ThreatReport | [`DataStructures.sol`](./contracts/src/libraries/DataStructures.sol) |
| `Roles` | Centralized role constants (MINTER, PAUSER, STRATEGY_MANAGER...) | [`Roles.sol`](./contracts/src/libraries/Roles.sol) |
| `OszillorErrors` | 33 custom error definitions (zero string reverts) | [`OszillorErrors.sol`](./contracts/src/libraries/OszillorErrors.sol) |

## ⚙️ CRE Workflows

All three workflows are TypeScript compiled to WASM via `@chainlink/cre-sdk`. They run as cron-triggered jobs on the Chainlink DON. Each writes reports to a dedicated on-chain receiver via `KeystoneForwarder`.

### W1 — Risk Scanner

[`cre-workflows/oszillor-risk-scanner/main.ts`](./cre-workflows/oszillor-risk-scanner/main.ts) | Cron: every 30 seconds

The primary risk assessment workflow. Aggregates multiple data sources, reasons about them with an LLM, reaches DON consensus, and writes a risk report on-chain.

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                    W1 DATA PIPELINE                             │
  │                                                                 │
  │  HTTPClient                                                     │
  │  ┌─────────────┐                                                │
  │  │  CoinGecko  │──► ETH price, stETH price,                    │
  │  │  /simple/   │    price change %, stETH/ETH ratio             │
  │  │  price      │                                                │
  │  └─────────────┘                                                │
  │                                                                 │
  │  HTTPClient                                                     │
  │  ┌─────────────┐                                                │
  │  │ DefiLlama   │──► Ethereum TVL, TVL change signal             │
  │  │ /v2/chains  │                                                │
  │  └─────────────┘                                                │
  │                                                                 │
  │  HTTPClient                                                     │
  │  ┌─────────────┐                                                │
  │  │ DefiLlama   │──► Cross-chain yield opportunities             │
  │  │ /pools      │    (top stablecoin strategies)                  │
  │  └─────────────┘                                                │
  │                                                                 │
  │  ConfidentialHTTPClient (secrets encrypted in DON)               │
  │  ┌─────────────┐                                                │
  │  │  News API   │──► Crypto news sentiment signal                │
  │  │  (premium)  │    API key never leaves DON nodes               │
  │  └─────────────┘                                                │
  │                                                                 │
  │  HTTPClient                                                     │
  │  ┌─────────────┐                                                │
  │  │  Groq LLM   │──► AI risk diagnosis, action recommendation   │
  │  │  llama-4-   │    "FATAL — recommend EMIT_PAUSE_AND_WITHDRAW" │
  │  │  scout      │                                                │
  │  └─────────────┘                                                │
  │                        │                                        │
  │                        ▼                                        │
  │            ┌───────────────────────┐                             │
  │            │ Compute (bigint only) │                             │
  │            │                       │                             │
  │            │ ETH drop:    0-35 pts │                             │
  │            │ stETH ratio: 0-30 pts │                             │
  │            │ TVL change:  0-15 pts │                             │
  │            │ News:        0-20 pts │                             │
  │            │ ──────────────────    │                             │
  │            │ Total:       0-100    │                             │
  │            └───────────┬───────────┘                             │
  │                        │                                        │
  │                        ▼                                        │
  │            ┌───────────────────────┐                             │
  │            │    DON Consensus      │                             │
  │            │                       │                             │
  │            │ riskScore: median     │                             │
  │            │ reasoning: common-    │                             │
  │            │   prefix aggregation  │                             │
  │            └───────────┬───────────┘                             │
  │                        │                                        │
  │                        ▼                                        │
  │            ┌───────────────────────┐                             │
  │            │      EVM Write        │                             │
  │            │                       │                             │
  │            │ RiskEngine.onReport(  │                             │
  │            │   riskScore,          │                             │
  │            │   confidence,         │                             │
  │            │   reasoningHash,      │                             │
  │            │   yieldOpportunities  │                             │
  │            │ )                     │                             │
  │            └───────────────────────┘                             │
  └─────────────────────────────────────────────────────────────────┘
```

**Fallback behavior**: If the LLM API fails, a deterministic reasoning string is generated from the risk score. If DefiLlama yields overflows the WASM buffer (~5-10MB response), yield data is gracefully omitted — it's enrichment, not critical.

### W2 — Event Sentinel

[`cre-workflows/oszillor-event-sentinel/main.ts`](./cre-workflows/oszillor-event-sentinel/main.ts) | Cron: every 15 seconds

Fast anomaly detection. Catches acute crashes that W1's 30-second cycle might miss.

```
  CoinGecko ──► ETH + stETH prices
                    │
                    ▼
            ┌───────────────┐
            │    Compute    │
            │               │
            │ Price drop    │──► > 5% in short window?
            │ stETH depeg   │──► ratio < 0.995?
            │ Reserve check │──► anomaly detected?
            └───────┬───────┘
                    │
              ┌─────┴─────┐
              │           │
          NO THREAT    THREAT
              │           │
           (no-op)        ▼
                   ┌──────────────┐
                   │ DON Consensus│
                   └──────┬───────┘
                          │
                          ▼
                   ┌──────────────┐
                   │  EVM Write   │
                   │              │
                   │ EventSentinel│
                   │  .onReport() │──► vault.pause()
                   └──────────────┘
```

### W3 — Rebase Executor

[`cre-workflows/oszillor-rebase-executor/main.ts`](./cre-workflows/oszillor-rebase-executor/main.ts) | Cron: every 5 minutes

Reads on-chain state, computes optimal portfolio allocation, and triggers rebalancing + share token rebase.

```
  ┌───────────────────────┐
  │  EVM Read             │
  │                       │
  │ RiskEngine            │
  │  .currentRiskScore()  │──► riskScore
  │                       │
  │ Vault                 │
  │  .totalAssets()       │──► vaultBalance
  │                       │
  │ Strategy              │
  │  .totalValueInEth()   │──► strategyValue
  └───────────┬───────────┘
              │
              ▼
  ┌───────────────────────┐
  │  Compute              │
  │                       │
  │ targetEthPct =        │    Risk → Allocation:
  │   f(riskScore)        │    SAFE:     90% ETH / 10% USDC
  │                       │    CAUTION:  70% ETH / 30% USDC
  │ rebaseFactor =        │    DANGER:   40% ETH / 60% USDC
  │   yield accrual +     │    CRITICAL:  0% ETH / 100% USDC
  │   NAV adjustment      │
  └───────────┬───────────┘
              │
              ▼
  ┌───────────────────────┐
  │  DON Consensus        │
  │  (median aggregation) │
  └───────────┬───────────┘
              │
              ▼
  ┌───────────────────────┐
  │  EVM Write            │
  │                       │
  │ RebaseExecutor        │
  │  .onReport(           │
  │    targetEthPct,      │──► vault.rebalance()
  │    rebaseFactor       │──► vault.triggerRebase()
  │  )                    │
  └───────────────────────┘
```

### CRE Capability Matrix

| Capability | W1 | W2 | W3 | W4 | Purpose |
| --- | --- | --- | --- | --- | --- |
| Cron Trigger | 30s | 15s | 5m | 60s | Scheduled execution |
| HTTP Trigger | — | — | — | Alert creation | On-demand via x402 API |
| HTTPClient | CoinGecko, DefiLlama (x2) | CoinGecko | — | — | Market data |
| ConfidentialHTTPClient | News API | — | — | — | Private credential access |
| HTTPClient → LLM | Groq API | — | — | — | AI risk reasoning |
| Compute | Risk scoring | Threat detection | Rebalance math | Alert evaluation | Bigint arithmetic |
| DON Consensus (median) | Risk score | Threat level | Rebalance params | — | Node agreement |
| DON Consensus (common-prefix) | AI reasoning | — | — | — | Text agreement |
| EVM Read | — | — | Vault + Strategy | **Cross-chain** (2 chains) | On-chain data |
| EVM Write | RiskEngine | EventSentinel | RebaseExecutor | AlertRegistry | On-chain reports |

## 💰 x402 Risk Intelligence API

OSZILLOR monetizes its risk data as a paid API. AI agents, DeFi protocols, and traders pay USDC micropayments via the **x402 HTTP payment protocol** to access real-time risk intelligence — creating protocol revenue from data that already exists on-chain.

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                     x402 PAYMENT FLOW                               │
  │                                                                     │
  │  AI Agent ──► GET /v1/risk/current ──► 402 Payment Required         │
  │     │                                       │                       │
  │     │         ┌─────────────────────┐       │ price: $0.001 USDC    │
  │     └────────►│  x402 Client        │◄──────┘ network: Base Sepolia │
  │               │  (auto-signs USDC   │                               │
  │               │   payment header)   │                               │
  │               └─────────┬───────────┘                               │
  │                         │                                           │
  │                         ▼                                           │
  │               ┌─────────────────────┐                               │
  │               │  Facilitator        │  Verifies payment on-chain    │
  │               │  (Coinbase x402)    │  Settles USDC to payTo addr   │
  │               └─────────┬───────────┘                               │
  │                         │                                           │
  │                         ▼                                           │
  │               ┌─────────────────────┐                               │
  │               │  Risk API Server    │  Reads vault state via viem   │
  │               │  (Express + x402)   │  from Ethereum Sepolia        │
  │               └─────────┬───────────┘                               │
  │                         │                                           │
  │                         ▼                                           │
  │               { riskScore: 72, riskLevel: "DANGER", ... }           │
  └─────────────────────────────────────────────────────────────────────┘
```

### W4 — Risk Alerts

[`cre-workflows/oszillor-risk-alerts/main.ts`](./cre-workflows/oszillor-risk-alerts/main.ts) | HTTP trigger + Cron: every 60 seconds

A dual-trigger CRE workflow that manages alert subscriptions. The HTTP trigger receives new alert rules from the x402 API server and writes them to the `AlertRegistry` on-chain. The cron trigger evaluates active rules against live risk data — performing **cross-chain EVM reads** from both Base Sepolia (AlertRegistry) and Ethereum Sepolia (OszillorVault).

```
  POST /v1/alerts ($0.01 USDC)
         │
         ▼
  ┌──────────────────┐     ┌─────────────────────┐
  │  Express Server  │────►│  CRE W4 HTTP Trigger │
  │  (x402-gated)    │     │                      │
  └──────────────────┘     │  ABI-encode alert    │
                           │  runtime.report()    │
                           │  writeReport() ──────┼──► AlertRegistry (Base Sepolia)
                           └──────────────────────┘

  Every 60s:
  ┌─────────────────────────────────────────────────────────────┐
  │  CRE W4 Cron Trigger                                        │
  │                                                             │
  │  EVM Read (Base Sepolia)                                    │
  │    AlertRegistry.getAllRuleIds()                             │
  │    AlertRegistry.isRuleActive(id)                           │
  │    AlertRegistry.getRule(id)                                │
  │                                                             │
  │  EVM Read (Eth Sepolia)  ◄── cross-chain!                  │
  │    OszillorVault.currentRiskScore()                         │
  │    OszillorVault.emergencyMode()                            │
  │                                                             │
  │  Compute: evaluate each rule against live state             │
  │    RISK_ABOVE 70? riskScore = 72 → TRIGGERED               │
  └─────────────────────────────────────────────────────────────┘
```

[`contracts/src/modules/AlertRegistry.sol`](./contracts/src/modules/AlertRegistry.sol) — CRE receiver on Base Sepolia that stores alert subscriptions. Supports `RISK_ABOVE`, `RISK_BELOW`, and `EMERGENCY` conditions with configurable thresholds and TTL-based expiry.

### API Endpoints

[`risk-api/src/server.ts`](./risk-api/src/server.ts) — Express server with `@x402/express` payment middleware.

| Method | Path | x402 Price | Returns |
|--------|------|-----------|---------|
| GET | `/health` | Free | Uptime, server status |
| GET | `/v1/risk/current` | $0.001 USDC | riskScore, riskLevel, confidence, timestamp |
| GET | `/v1/risk/portfolio` | $0.005 USDC | NAV, ETH/USDC allocation, strategy positions |
| GET | `/v1/risk/full` | $0.01 USDC | Combined risk + portfolio + allocations |
| POST | `/v1/alerts` | $0.01 USDC | Create alert subscription via CRE W4 |
| GET | `/v1/alerts/:id` | $0.001 USDC | Alert subscription status |

```bash
# Start the API server
cd risk-api && bun run dev

# Test (free endpoint)
curl http://localhost:4021/health

# Test (x402-gated — returns 402 without payment)
curl http://localhost:4021/v1/risk/current
```

### AI Agent (Coinbase AgentKit)

[`risk-api/agent/`](./risk-api/agent/) — A real autonomous AI agent built with **Coinbase AgentKit + LangChain + Claude Sonnet** that consumes the x402 Risk API. The agent has a CDP-managed wallet on Base Sepolia and autonomously pays for risk intelligence data.

```
  ┌───────────────────────────────────────────────────────────────────┐
  │                    AUTONOMOUS RISK AGENT                          │
  │                                                                   │
  │  ┌────────────────┐    ┌─────────────────┐    ┌───────────────┐  │
  │  │  Claude Sonnet LLM    │───►│  LangChain      │───►│  AgentKit     │  │
  │  │  (reasoning)   │    │  ReAct Agent     │    │  Tools        │  │
  │  └────────────────┘    └─────────────────┘    └───────┬───────┘  │
  │                                                       │          │
  │                                          ┌────────────┼──────┐   │
  │                                          │            │      │   │
  │                                          ▼            ▼      ▼   │
  │                                    ┌──────────┐ ┌────────┐ ┌───┐ │
  │                                    │  x402    │ │ Wallet │ │ERC│ │
  │                                    │  Action  │ │ Action │ │20 │ │
  │                                    │ Provider │ │Provider│ │   │ │
  │                                    └────┬─────┘ └────────┘ └───┘ │
  │                                         │                        │
  │                            ┌────────────┴────────────┐           │
  │                            ▼                         ▼           │
  │                     GET /v1/risk/current      POST /v1/alerts    │
  │                     → 402 → auto-pay USDC     → 402 → auto-pay  │
  │                     → risk data returned      → alert created    │
  └───────────────────────────────────────────────────────────────────┘
```

Two modes:
- **Interactive Chat** (`bun run start`) — Ask questions, agent fetches and pays for data on demand
- **Autonomous** (`bun run auto`) — Agent runs full risk monitoring cycle independently, escalating based on risk level

```bash
# Setup
cd risk-api/agent
cp .env.example .env  # Fill in ANTHROPIC_API_KEY + CDP credentials
bun install

# Interactive mode
bun run start
# "Check the current ETH risk level"
# "Get the full portfolio report"
# "Create an alert if risk goes above 70"

# Autonomous mode
bun run auto
```

There is also a lightweight demo without an LLM at [`risk-api/demo/agent-demo.ts`](./risk-api/demo/agent-demo.ts) that uses `@x402/fetch` for direct x402 auto-payment ($0.026 USDC total).

## 🧠 AI Integration

W1 sends all market telemetry to Groq's `llama-4-scout` LLM for risk reasoning. The AI receives:

- Live ETH and stETH prices from CoinGecko
- stETH/ETH ratio deviation
- Lido reserve status
- News sentiment from ConfidentialHTTPClient

The AI produces a structured 3-sentence diagnosis: (1) exploit analysis, (2) risk level declaration, (3) action recommendation.

DON nodes reach consensus on the AI output using `commonPrefixAggregation` — nodes must agree on the reasoning text. The SHA-256 hash of the reasoning is written on-chain as part of the risk report, creating a verifiable audit trail of AI decisions.

If the LLM is unavailable, a deterministic fallback is generated from the numerical risk score. The system never blocks on AI availability.

## 🔒 Privacy Integration

W1 uses `ConfidentialHTTPClient` to fetch premium news sentiment data. The API key is stored as an encrypted DON secret — it never appears in workflow source code, never leaves DON nodes, and is not visible on-chain.

This enables proprietary data sources to feed into risk decisions without exposing credentials or data publicly.

## 🌉 Cross-Chain Architecture (CCIP)

OSZILLOR uses a hub-spoke CCIP topology for cross-chain OSZ token bridging and rebase propagation:

```
                           ┌──────────────────────┐
                           │     Hub Chain         │
                           │  (Base Sepolia)       │
                           │                       │
                           │  OszillorVault        │
                           │  VaultStrategy        │
                           │  OszillorToken        │
                           │  RiskEngine           │
                           │  EventSentinel        │
                           │  RebaseExecutor       │
                           │  OszillorTokenPool    │
                           │  HubPeer ◄────────────┼──── CRE W1/W2/W3
                           └──────┬────────┬───────┘
                          CCIP    │        │    CCIP
                     ┌────────────┘        └────────────┐
                     ▼                                  ▼
           ┌──────────────────┐              ┌──────────────────┐
           │  Spoke Chain     │              │  Spoke Chain     │
           │  (Base Sepolia)  │              │  (Avalanche)     │
           │                  │              │                  │
           │  OszillorToken   │              │  OszillorToken   │
           │  TokenPool       │              │  TokenPool       │
           │  SpokePeer       │              │  SpokePeer       │
           └──────────────────┘              └──────────────────┘

  Token bridging: lock shares on source ──CCIP──► mint shares on dest
  Rebase sync:    hub broadcasts new index ──► spokes update locally
```

`OszillorTokenPool` converts between rebased amounts and underlying shares during bridging. A naive lock/unlock pool would break because rebase indices may differ across chains.

## 🚦 Risk State Machine

The `RiskEngine` maintains a 4-state risk machine. State transitions are monotonically validated — the system can't jump from SAFE to CRITICAL in one report (delta clamping).

```
   Risk Score:    0 ──────── 25 ──────── 50 ──────── 75 ──────── 100
                  │           │           │           │           │
   State:       SAFE       CAUTION     DANGER     CRITICAL
                  │           │           │           │
   ETH Alloc:   90%         70%         40%          0%
   USDC Alloc:  10%         30%         60%        100%
                  │           │           │           │
   Actions:    Max yield   Moderate    Heavy      Emergency
                           hedge       hedge      withdrawal
```

Reports are validated before state transitions:
- **Rate limit**: minimum cooldown between updates
- **Confidence gate**: score must meet minimum confidence threshold
- **Delta clamp**: score can't change by more than `maxDelta` per report
- **CRE 4-check**: transmitter, signer, workflow ID, report format

## ⚖️ Rebalance Logic

When W3 triggers a rebalance, the vault adjusts the strategy's ETH/USDC split:

```
  Current State                    After Rebalance (DANGER → 40% ETH)
  ┌────────────────────────┐       ┌────────────────────────┐
  │ VaultStrategy          │       │ VaultStrategy          │
  │                        │       │                        │
  │  ETH: 10.0  (100%)     │  ──►  │  ETH:  4.0  (40%)     │
  │  USDC: 0.0  (0%)       │       │  USDC: 6.0  (60%)     │
  │                        │       │  (swapped via Uniswap) │
  │  NAV: 10.0 ETH         │       │  NAV: 10.0 ETH        │
  └────────────────────────┘       └────────────────────────┘

  Swap uses Chainlink ETH/USD feed for slippage protection,
  NOT spot price.
```

## 🧪 Testing

**305 tests** across 12 suites. **Zero failures**.

| Suite | Tests | Type |
| --- | --- | --- |
| OszillorVaultTest | 64 | Unit |
| ModulesTest | 47 | Unit (RiskEngine, EventSentinel, RebaseExecutor, CREReceiver) |
| OszillorTokenTest | 41 | Unit |
| VaultStrategyTest | 32 | Unit |
| LibrariesTest | 32 | Unit (ShareMath, RiskMath, CCIPOperations) |
| AlertRegistryTest | 20 | Unit (CRE 4-check, TTL expiry, USDC withdrawal) |
| OszillorTokenPoolTest | 18 | Unit |
| PeersTest | 13 | Unit (HubPeer, SpokePeer) |
| OszillorInvariantTest | 7 | Invariant (handler-based, fail-on-revert) |
| CREIntegrationTest | 6 | Integration (full W1→W2→W3 pipeline) |
| ShareMathFuzzTest | 5 | Fuzz (10,000 runs per property) |

Key invariants tested:
- `totalShares × rebaseIndex = totalSupply` (always)
- Vault total assets >= sum of deposits (no value loss)
- Risk state machine transitions are monotonically valid
- Strategy value + vault idle = total NAV

```bash
forge test               # All 305 tests
forge test -vvv          # Verbose
forge test --match-contract OszillorInvariantTest   # Invariant suite
```

CRE workflow tests (TypeScript):

```bash
cd cre-workflows/tests && bun test
```

## 🛡️ Formal Verification

[Certora](https://www.certora.com/) specs for `OszillorToken` and `OszillorVault`:

```bash
export CERTORAKEY=<personal_access_key>
certoraRun ./certora/conf/OszillorToken.conf
certoraRun ./certora/conf/OszillorVault.conf
```

Specs verify rebase index consistency, deposit/withdraw accounting invariants, and access control enforcement. See [`certora/spec/`](./contracts/certora/spec/).

## 🕵️ Security Audit

A comprehensive security audit identified 36 findings across severity levels. All findings reviewed and addressed. Full report: [`.references/security-audit.md`](./.references/security-audit.md).

## 🌐 Testnet Deployment

Deployed to **two chains** — full hub on Base Sepolia (primary) and Ethereum Sepolia. All contracts live with on-chain bytecode verified via `cast code`.

### Base Sepolia (Primary Hub)

| Contract | Address | Explorer |
| --- | --- | --- |
| OszillorVault | `0xa120B2d1acdc17FbB6C49BD222C05D74e1b0691d` | [View](https://sepolia.basescan.org/address/0xa120B2d1acdc17FbB6C49BD222C05D74e1b0691d) |
| OszillorToken | `0x86fFd6Bd8F9c6E89B7E5D7e310E6D0057fF560E0` | [View](https://sepolia.basescan.org/address/0x86fFd6Bd8F9c6E89B7E5D7e310E6D0057fF560E0) |
| VaultStrategy | `0x495BAD77D91afA0fc03Fe24A0C074966d2e34A96` | [View](https://sepolia.basescan.org/address/0x495BAD77D91afA0fc03Fe24A0C074966d2e34A96) |
| RiskEngine | `0x69A213a7BcB23d8693f558bAcD6192F5605BEFAD` | [View](https://sepolia.basescan.org/address/0x69A213a7BcB23d8693f558bAcD6192F5605BEFAD) |
| EventSentinel | `0x424FB4395a95153802B3A4c1cfb2514B0aBF8732` | [View](https://sepolia.basescan.org/address/0x424FB4395a95153802B3A4c1cfb2514B0aBF8732) |
| RebaseExecutor | `0x35Bf9dE18C872Ae9B5E1B55425390ADef31514DC` | [View](https://sepolia.basescan.org/address/0x35Bf9dE18C872Ae9B5E1B55425390ADef31514DC) |
| AlertRegistry | `0x62998075686658C6069de79A05461Aed91663265` | [View](https://sepolia.basescan.org/address/0x62998075686658C6069de79A05461Aed91663265) |
| OszillorTokenPool | `0x63F47EFc17183CB30bd72D3ecA3122850d1084A7` | [View](https://sepolia.basescan.org/address/0x63F47EFc17183CB30bd72D3ecA3122850d1084A7) |
| HubPeer | `0x9269Da439a4fBc2601E4f5BC4A9AEeD292319008` | [View](https://sepolia.basescan.org/address/0x9269Da439a4fBc2601E4f5BC4A9AEeD292319008) |
| MockLido | `0x800527792FDeC4aEb8B4fd510C669dacA4e7309D` | [View](https://sepolia.basescan.org/address/0x800527792FDeC4aEb8B4fd510C669dacA4e7309D) |

### Ethereum Sepolia (Secondary Hub)

| Contract | Address | Explorer |
| --- | --- | --- |
| OszillorVault | `0xbb6b66c2bd6c3e53869726f1eadc8cf824f8ff1d` | [View](https://sepolia.etherscan.io/address/0xbb6b66c2bd6c3e53869726f1eadc8cf824f8ff1d#code) |
| OszillorToken | `0xd17107316431bc9626bad4d25f584fae5df1630a` | [View](https://sepolia.etherscan.io/address/0xd17107316431bc9626bad4d25f584fae5df1630a#code) |
| VaultStrategy | `0xdf6e5ebcaaff2a2a40c4a3e6b89e936a13747ccf` | [View](https://sepolia.etherscan.io/address/0xdf6e5ebcaaff2a2a40c4a3e6b89e936a13747ccf#code) |
| RiskEngine | `0x31b3cfb370de8b7b13bda40f105901ad7a68ebb0` | [View](https://sepolia.etherscan.io/address/0x31b3cfb370de8b7b13bda40f105901ad7a68ebb0#code) |
| EventSentinel | `0x0490c9a22e1dc8084fe18f8977a81bb42e5b341f` | [View](https://sepolia.etherscan.io/address/0x0490c9a22e1dc8084fe18f8977a81bb42e5b341f#code) |
| RebaseExecutor | `0xeaa638afeb35d2020907856a8a4d5d092037d851` | [View](https://sepolia.etherscan.io/address/0xeaa638afeb35d2020907856a8a4d5d092037d851#code) |
| MockLido | `0x02bdfd4659386db44846cb0a04634b823bf8bbeb` | [View](https://sepolia.etherscan.io/address/0x02bdfd4659386db44846cb0a04634b823bf8bbeb#code) |
| OszillorTokenPool | `0x031499719b6cdc5705ab1628bc3eea6b98a90a62` | [View](https://sepolia.etherscan.io/address/0x031499719b6cdc5705ab1628bc3eea6b98a90a62#code) |
| HubPeer | `0xf42a60dd901b94223305f5fa7051960d8c09dbdf` | [View](https://sepolia.etherscan.io/address/0xf42a60dd901b94223305f5fa7051960d8c09dbdf#code) |

Deployed with [`DeployHub.s.sol`](./contracts/script/deploy/DeployHub.s.sol). AlertRegistry deployed with [`DeployAlertRegistry.s.sol`](./contracts/script/deploy/DeployAlertRegistry.s.sol). Roles granted with [`SetupRoles.s.sol`](./contracts/script/interactions/SetupRoles.s.sol). Validated with [`ValidateDeployment.s.sol`](./contracts/script/interactions/ValidateDeployment.s.sol).

## 🎬 E2E Demo

The demo script runs a full incident response scenario with real on-chain transactions. Supports both Base Sepolia (default) and Ethereum Sepolia. Every CRE workflow writes a verifiable transaction on-chain.

| Step | What Happens | On-chain TX |
| --- | --- | --- |
| **Step 0** | Seed risk state (ensures vault accepts deposits) | 1 tx |
| **Step 1** | User deposits WETH, funds routed to strategy, OSZ minted | 1 tx |
| **Step 2** | Simulated Lido stETH depeg/exploit (rocket crash animation) | — |
| **Step 3** | W1 Risk Scanner — live Groq LLM diagnosis, risk report to RiskEngine | 1 tx |
| **Step 4** | W2 Event Sentinel — crash detection, emergency pause to EventSentinel | 1 tx |
| **Step 5** | W3 Rebase Executor — fund rescue, rebalance report to RebaseExecutor | 1 tx |
| **Step 6** | W4 Risk Alerts — cross-chain alert evaluation (Base Sepolia only) | — |
| **Step 7** | Final verification — before/after balance diffs, all tx links | — |

```
  PROOF OF EXECUTION — BASE SEPOLIA LIVE TRANSACTIONS
  ══════════════════════════════════════════════════════════════════
  1. User Deposit      https://sepolia.basescan.org/tx/0x...
  2. AI Risk Report    https://sepolia.basescan.org/tx/0x93bbfac4...
  3. Emergency Pause   https://sepolia.basescan.org/tx/0x49c967ee...
  4. Fund Rescue       https://sepolia.basescan.org/tx/0x9ba4f337...
```

```bash
make demo-e2e                              # Base Sepolia (default)
make demo-e2e-sepolia                      # Ethereum Sepolia
bash demo/e2e-master.sh --chain base-sepolia  # Direct invocation
```

## 🔗 Chainlink File References

Files that use Chainlink services:

| File | Chainlink Service |
| --- | --- |
| [`src/modules/CREReceiver.sol`](./contracts/src/modules/CREReceiver.sol) | CRE (KeystoneForwarder validation) |
| [`src/modules/RiskEngine.sol`](./contracts/src/modules/RiskEngine.sol) | CRE (W1 report receiver) |
| [`src/modules/EventSentinel.sol`](./contracts/src/modules/EventSentinel.sol) | CRE (W2 report receiver) |
| [`src/modules/RebaseExecutor.sol`](./contracts/src/modules/RebaseExecutor.sol) | CRE (W3 report receiver) |
| [`src/core/VaultStrategy.sol`](./contracts/src/core/VaultStrategy.sol) | Price Feeds (ETH/USD) |
| [`src/adapters/OszillorTokenPool.sol`](./contracts/src/adapters/OszillorTokenPool.sol) | CCIP (token pool) |
| [`src/peers/HubPeer.sol`](./contracts/src/peers/HubPeer.sol) | CCIP (cross-chain messaging) |
| [`src/peers/SpokePeer.sol`](./contracts/src/peers/SpokePeer.sol) | CCIP (cross-chain messaging) |
| [`src/peers/OszillorPeer.sol`](./contracts/src/peers/OszillorPeer.sol) | CCIP (base peer logic) |
| [`cre-workflows/oszillor-risk-scanner/main.ts`](./cre-workflows/oszillor-risk-scanner/main.ts) | CRE (HTTPClient, ConfidentialHTTPClient, Consensus, EVM Write) |
| [`cre-workflows/oszillor-event-sentinel/main.ts`](./cre-workflows/oszillor-event-sentinel/main.ts) | CRE (HTTPClient, Consensus, EVM Write) |
| [`cre-workflows/oszillor-rebase-executor/main.ts`](./cre-workflows/oszillor-rebase-executor/main.ts) | CRE (EVM Read, Consensus, EVM Write) |
| [`src/modules/AlertRegistry.sol`](./contracts/src/modules/AlertRegistry.sol) | CRE (W4 report receiver) |
| [`cre-workflows/oszillor-risk-alerts/main.ts`](./cre-workflows/oszillor-risk-alerts/main.ts) | CRE (HTTP Trigger, Cron, cross-chain EVM Read, EVM Write) |
| [`risk-api/src/server.ts`](./risk-api/src/server.ts) | x402 (payment middleware, Base Sepolia USDC) |

## 💻 Local Development

### Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`, `cast`)
- [Bun](https://bun.sh/) (CRE workflows, Risk API, Agent, Frontend)
- [CRE CLI](https://docs.chain.link/cre) (`cre workflow simulate`)
- GNU Make (included on macOS/Linux, use Git Bash on Windows)

### Quick Start

```bash
make                  # Show all available commands
make install-all      # Install ALL dependencies (Foundry + CRE + API + Agent + Frontend)
make test-all         # Run ALL tests (305 Foundry + 4 CRE simulations)
make showcase         # Full project showcase for reviewers
```

### Makefile Commands

| Category | Command | Description |
|----------|---------|-------------|
| **Setup** | `make setup` | Install Foundry deps + create deployer keystore |
| | `make install-all` | Install ALL project dependencies |
| **Build** | `make build` | Compile all Solidity contracts |
| | `make build-cre` | Compile all 4 CRE workflows to WASM |
| | `make build-all` | Build everything (Solidity + CRE WASM) |
| **Test** | `make test` | Run all 305 Solidity tests |
| | `make test-summary` | Run tests with per-suite summary table |
| | `make test-unit` | Unit tests only |
| | `make test-fuzz` | Fuzz tests only (10,000 runs each) |
| | `make test-invariant` | Invariant tests (stateful fuzzing) |
| | `make test-integration` | CRE integration tests |
| | `make test-gas` | Tests with gas report |
| | `make test-all` | ALL tests (Foundry + CRE W1-W4) |
| **CRE** | `make simulate-w1` | Simulate W1 Risk Scanner |
| | `make simulate-w2` | Simulate W2 Event Sentinel |
| | `make simulate-w3` | Simulate W3 Rebase Executor |
| | `make simulate-w4-cron` | Simulate W4 Alerts (cron trigger) |
| | `make simulate-w4-http` | Simulate W4 Alerts (HTTP trigger) |
| | `make simulate-all` | Simulate all 4 workflows |
| **API** | `make api-dev` | Start Risk API with hot reload (port 4021) |
| | `make api-test` | Test all 6 API endpoints |
| | `make api-demo` | Run x402 payment demo |
| **Agent** | `make agent-chat` | Interactive AI agent (Claude + AgentKit) |
| | `make agent-auto` | Autonomous risk monitoring agent |
| **Frontend** | `make frontend-dev` | Start Next.js dev server (port 3000) |
| | `make frontend-build` | Build frontend for production |
| **Deploy** | `make deploy-base` | Deploy all contracts to Base Sepolia |
| | `make deploy-hub` | Deploy hub to Ethereum Sepolia |
| | `make deploy-alerts` | Deploy AlertRegistry to Base Sepolia |
| | `make deploy-all` | Full pipeline: deploy + roles + validate |
| **Demo** | `make showcase` | Full project showcase (tests + simulations) |
| | `make demo-e2e` | Run E2E demo on Base Sepolia (live txs) |
| | `make demo-e2e-sepolia` | Run E2E demo on Ethereum Sepolia |
| **Utils** | `make status` | Show project health (git, builds, deps) |
| | `make sizes` | Show contract deployment sizes |
| | `make fmt` | Format Solidity files |

### Environment Setup

```bash
# Solidity contracts
cd contracts && cp .env.example .env     # Fill: DEPLOYER_ADDRESS, RPC URLs

# Risk API server
cd risk-api && cp .env.example .env      # Fill: PAY_TO_ADDRESS, RPC URL

# AI Agent
cd risk-api/agent && cp .env.example .env  # Fill: ANTHROPIC_API_KEY, CDP credentials
```

### Run Everything

```bash
# Terminal 1: Risk API server
make api-dev

# Terminal 2: Test the API
make api-test

# Terminal 3: AI Agent (interactive)
make agent-chat

# Terminal 4: Frontend
make frontend-dev
```

## 🖥️ Frontend

Path: [`frontend/`](./frontend/) | Next.js 14, Tailwind, wagmi + viem, RainbowKit, recharts, framer-motion.

```bash
cd frontend && npm install && npm run dev
```

Dashboard includes wallet connect, deposit/withdraw, live risk gauge, position overview, and yield intelligence panel.

## 🗺️ Repository Map

```
contracts/
  src/                          # 3,523 lines of Solidity
    core/                       #   OszillorVault, VaultStrategy, OszillorToken
    modules/                    #   RiskEngine, EventSentinel, RebaseExecutor, CREReceiver
    adapters/                   #   OszillorTokenPool
    peers/                      #   HubPeer, SpokePeer, OszillorPeer
    libraries/                  #   ShareMath, RiskMath, CCIPOperations, Roles, Errors
    interfaces/                 #   All contract interfaces
  test/                         # 305 tests
    unit/                       #   Per-contract unit tests
    fuzz/                       #   Property-based fuzz tests (10k runs)
    invariant/                  #   Handler-based invariant tests
    integration/                #   CRE pipeline integration tests
    mocks/                      #   MockLido, MockStrategy, MockUniswapRouter
  script/                       # Deployment and interaction scripts
  certora/                      # Formal verification specs

cre-workflows/
  oszillor-risk-scanner/        # W1: multi-signal risk + AI + yields
  oszillor-event-sentinel/      # W2: crash detection + emergency pause
  oszillor-rebase-executor/     # W3: portfolio rebalance + rebase
  oszillor-risk-alerts/         # W4: alert subscriptions (HTTP + Cron, cross-chain)
  contracts/abi/                # Shared ABIs for EVM read/write
  tests/                        # Encoding + risk-math tests

risk-api/
  src/                          # Express server + x402 payment middleware
    routes/                     #   health (free), risk (3), alerts (2)
    services/                   #   vault-reader (viem), risk-formatter
  agent/                        # Coinbase AgentKit + LangChain + Claude Sonnet
    chatbot.ts                  #   Interactive chat mode
    autonomous.ts               #   Autonomous risk monitoring
  demo/                         # Lightweight x402-fetch demo script

demo/
  e2e-master.sh                 # Full E2E demo with live Sepolia txs

frontend/                       # Next.js dashboard
```

## ⚠️ Known Issues

**MockLido does not generate real yield** — Lido stETH is unavailable on Sepolia. `MockLido` accepts WETH deposits and tracks balances but generates no actual staking yield. W3 uses a configurable `stakingApyBps` to simulate yield accrual.

**CRE workflows run in simulation mode** — CRE DON deployment requires early access. Workflows run via `cre workflow simulate --broadcast`, which executes locally but writes real transactions to Sepolia. On-chain behavior is identical.

**DefiLlama yields can overflow WASM buffer** — The `/pools` endpoint returns ~5-10MB. If the fetch fails, yield data is omitted. Core risk scoring (ETH price, stETH ratio, TVL, news) is unaffected.

## 🚀 Future Developments

- Deploy spoke contracts to Base Sepolia and Avalanche Fuji for live cross-chain
- Integrate real Lido stETH (mainnet fork or testnet availability)
- Additional yield strategies (Aave, Compound) in VaultStrategy
- CRE DON deployment when early access is granted
- CCIP calldata compression (solady.libZip)
- Additional Certora specs for VaultStrategy and peer contracts

## 🧗 Challenges

**DefiLlama response too large for CRE WASM** — `yields.llama.fi/pools` returns all DeFi pools (~5-10MB). The CRE WASM buffer can't hold this. Solved by making the yield fetch fault-tolerant — the system degrades gracefully, since core risk scoring uses smaller endpoints.

**DON consensus with LLM output** — Different DON nodes may receive slightly different LLM responses. We use `commonPrefixAggregation` for AI text (longest common prefix across nodes) and `median` aggregation for numerical values.

**Atomic routing with ERC-4626** — Standard ERC-4626 expects `totalAssets()` to reflect the vault's balance. Since deposits route immediately to the strategy, `totalAssets()` must include `strategy.totalValueInEth()`, adding gas cost but ensuring correct share pricing.

**Rebase token CCIP bridging** — Bridging a rebase token requires converting between rebased amounts and underlying shares. `OszillorTokenPool` converts to shares on lock, converts back on unlock using local rebase index.

**Coordinating three independent workflows** — W1, W2, W3 cooperate through shared on-chain state rather than inter-workflow messaging (which CRE doesn't support). W1 writes risk scores → W2 reads risk to decide severity → W3 reads risk to calculate allocation.
