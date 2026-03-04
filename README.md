<p align="center">
  <img src="https://img.shields.io/badge/OSZILLOR-Protocol-6C5CE7?style=for-the-badge&labelColor=0D1117" alt="OSZILLOR" />
</p>

<h1 align="center">
  <br>
  ◈ OSZILLOR
  <br>
</h1>

<p align="center">
  <b>Risk-Reactive Rebase Token Protocol</b>
  <br>
  <i>Your wallet balance IS your risk dashboard.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Solidity-0.8.24-363636?style=flat-square&logo=solidity" alt="Solidity" />
  <img src="https://img.shields.io/badge/Foundry-Framework-DEA584?style=flat-square" alt="Foundry" />
  <img src="https://img.shields.io/badge/Chainlink-CRE%20%2B%20CCIP-375BD2?style=flat-square&logo=chainlink" alt="Chainlink" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/Tests-47%20Passing-brightgreen?style=flat-square" alt="Tests" />
</p>

<p align="center">
  <a href="#how-it-works">How It Works</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#testing">Testing</a> •
  <a href="#security">Security</a> •
  <a href="#roadmap">Roadmap</a>
</p>

---

## The Problem

DeFi users have **no autonomous protection** against risk. Existing protocols either:
- Offer static yield with no risk awareness (Aave, Lido)
- Provide read-only dashboards that require manual action (Forta, Hypernative)
- Rebase based on price oracles, not real risk intelligence (Ampleforth, OHM)

**When a protocol gets exploited, users find out on Twitter — after their funds are gone.**

## The Solution

OSZILLOR is the first protocol where **confidential AI risk assessment drives autonomous token rebasing** across multiple chains.

```
  ┌─────────────────────────────────────────────┐
  │          SAFE (score 0-39)                  │
  │  ██████████████████████████  +yield         │
  │          your OSZ balance grows             │
  ├─────────────────────────────────────────────┤
  │          CAUTION (score 40-69)              │
  │  █████████████               +half yield    │
  │          your OSZ balance grows slowly      │
  ├─────────────────────────────────────────────┤
  │          DANGER (score 70-89)               │
  │  ░░░░░░░░░░░░░░░░░░░░░░░░░  zero yield    │
  │          your OSZ balance holds steady      │
  ├─────────────────────────────────────────────┤
  │          CRITICAL (score 90-100)            │
  │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  -0.5%         │
  │          protocol de-risks autonomously     │
  └─────────────────────────────────────────────┘
```

## How It Works

```
User deposits USDC ──► Receives OSZ rebase tokens
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    ┌──────────┐       ┌──────────┐       ┌──────────┐
    │  CRE W1  │       │  CRE W2  │       │  CRE W3  │
    │   Risk   │       │  Event   │       │  Rebase  │
    │ Scanner  │       │ Sentinel │       │ Executor │
    │  (60s)   │       │ (events) │       │ (5 min)  │
    └────┬─────┘       └────┬─────┘       └────┬─────┘
         │                  │                   │
         ▼                  ▼                   ▼
    AI risk score      Emergency halt      Apply rebase
    via TEE/DON        on threats           factor to
    consensus          (depegs, hacks)      rebaseIndex
         │                  │                   │
         └──────────────────┼───────────────────┘
                            ▼
                   OSZ balance adjusts
                   automatically ◈
```

**Three Chainlink CRE workflows** run autonomously:

| Workflow | Trigger | What It Does | CRE Capabilities |
|----------|---------|-------------|-------------------|
| **W1** Risk Scanner | Cron / 60s | AI scores DeFi risk (0-100) inside TEE | Confidential HTTP, Compute (Gemini), DON Consensus |
| **W2** Event Sentinel | EVM Logs | Detects depegs, exploits, TVL crashes | EVM Log Trigger, HTTP, EVM Read |
| **W3** Rebase Executor | Cron / 5min | Applies risk-adjusted yield as rebase | EVM Read, Compute, EVM Write |

> **11 CRE capabilities** across 3 workflows. The AI risk model runs inside a **Trusted Execution Environment** — not even CRE node operators can see the strategy.

## Architecture

```
contracts/src/
  libraries/          Layer 1 — Pure logic, no state
    ├── Roles.sol              9 granular RBAC roles
    ├── DataStructures.sol     Shared enums & structs
    ├── OszillorErrors.sol     22 custom errors (zero string reverts)
    ├── ShareMath.sol          Share ↔ amount conversion (inflation-proof)
    ├── RiskMath.sol            Risk tiers, factor bounds, rebase calc
    └── CCIPOperations.sol     CCIP message building & fee handling

  interfaces/         Layer 2 — Contract communication boundaries
  modules/            Layer 3 — Reusable behaviors (pause, CRE, fees)
  core/               Layer 4 — OszillorToken + OszillorVault
  peers/              Layer 5 — Hub + Spoke CCIP orchestration
  adapters/           Layer 6 — Risk data source plugins
```

### Hub-Spoke Topology

```
                    ┌─────────────────┐
                    │   HUB (Base)    │
                    │                 │
                    │  OszillorToken  │
                    │  OszillorVault  │
                    │  RiskEngine     │
                    │  RebaseExecutor │
                    │  EventSentinel  │
                    └────────┬────────┘
                             │ CCIP
                    ┌────────┴────────┐
                    │                 │
              ┌─────┴─────┐   ┌──────┴─────┐
              │  SPOKE 1  │   │  SPOKE 2   │
              │ Arbitrum  │   │  Optimism  │
              │           │   │            │
              │ SpokePeer │   │ SpokePeer  │
              │ SpokeToken│   │ SpokeToken │
              └───────────┘   └────────────┘
```

### Security Model

```
DEFAULT_ADMIN_ROLE (multisig, 5-day transfer delay)
  ├── CONFIG_ADMIN_ROLE          → risk adapters, registry
  ├── CROSS_CHAIN_ADMIN_ROLE     → CCIP spoke registration
  ├── RISK_MANAGER_ROLE          → RiskEngine + Vault (mint/burn)
  ├── REBASE_EXECUTOR_ROLE       → RebaseExecutor only
  ├── SENTINEL_ROLE              → EventSentinel only
  ├── EMERGENCY_PAUSER_ROLE      → dedicated hot wallet
  ├── EMERGENCY_UNPAUSER_ROLE    → DIFFERENT address (anti-hostage)
  ├── FEE_RATE_SETTER_ROLE       → governance multisig
  └── FEE_WITHDRAWER_ROLE        → treasury multisig
```

> **9 granular roles.** No god keys. Each CRE workflow has its own receiver contract — compromise of one cannot affect the others (bulkhead pattern).

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Git

### Installation

```bash
git clone https://github.com/vyqno/oszillor.git
cd oszillor/contracts

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts --no-commit
git clone --depth 1 https://github.com/smartcontractkit/ccip.git lib/chainlink
git clone --depth 1 https://github.com/smartcontractkit/chainlink-local.git lib/chainlink-local

# Verify
forge build
```

> **Note:** Chainlink Solidity contracts are sourced from the archived `smartcontractkit/ccip` repo — the main `smartcontractkit/chainlink` repo no longer contains Solidity contracts at root.

### Build

```bash
cd contracts
forge build
```

### Test

```bash
# All tests
forge test

# Verbose output
forge test -vvv

# Only fuzz tests
forge test --match-path test/fuzz/*

# Only unit tests
forge test --match-path test/unit/*
```

## Testing

### Test Pyramid

```
  ┌───────────────┐
  │    Certora     │  Formal verification — 7 invariants
  ├───────────────┤
  │   Invariant    │  Stateful fuzz via Handler pattern
  ├───────────────┤
  │     Fuzz       │  Stateless fuzz (ShareMath, RiskMath)
  ├───────────────┤
  │     Unit       │  Every public/external function
  ├───────────────┤
  │    Slither     │  Static analysis on every commit
  └───────────────┘
```

### Current Coverage

| Suite | Tests | Status |
|-------|-------|--------|
| Unit (Libraries) | 32 | Passing |
| Fuzz (ShareMath) | 5 × 10K runs | Passing |
| Fuzz (RiskMath) | 10 × 10K runs | Passing |
| **Total** | **47** | **All green** |

### Critical Invariants (to be formally verified)

1. `sum(sharesOf(all_users)) == token.totalShares()`
2. `deposit(X) then withdraw → returns X ± 1 wei`
3. `rebase(factor)` only if factor ∈ `[0.99e18, 1.01e18]`
4. `emergencyMode == true → deposit() always reverts`
5. `rebase()` callable ONLY by `REBASE_EXECUTOR_ROLE`
6. `deposit(amount >= MIN_DEPOSIT) → shares > 0`
7. `rebaseIndex` always ∈ `[1e16, 1e20]`

## Security

### Audit Status

- **36 findings** identified during design-phase security analysis
- **6 Critical, 11 High, 10 Medium, 5 Low, 4 Info**
- All findings have remediation code patterns embedded in the implementation
- External audit planned before mainnet deployment

### Key Security Features

| Feature | Protection Against |
|---------|-------------------|
| Virtual share offset | First-depositor inflation attack (CRIT-01) |
| Factor + index bounds | Rebase index overflow to zero (CRIT-02) |
| Fail-closed init (CAUTION) | Exploitation before first CRE report (CRIT-03) |
| Spoke staleness threshold | Stale risk state exploitation on L2s (CRIT-04) |
| Confidential Compute (TEE) | Rebase sandwich MEV attacks (CRIT-05) |
| Internal asset accounting | Donation attack via direct transfer (CRIT-06) |
| Share-based allowances | Stale ERC20 allowances after rebase (HIGH-01) |
| Delta clamping (max 20) | Oracle manipulation via rapid updates (HIGH-05) |
| Immutable CRE params | Workflow redirect attacks (MED-03) |
| CCIP ordered execution | Out-of-order state corruption (HIGH-09) |

### Immutable Contracts

OSZILLOR uses **no proxies, no upgradeability**. All contracts are immutable once deployed. If a critical vulnerability is discovered post-deployment, the emergency system returns assets to users and a new deployment is created.

## How OSZILLOR Differs

| Protocol | What It Does | OSZILLOR Advantage |
|----------|-------------|-------------------|
| Ampleforth / OHM | Price-oracle rebases | Multi-dimensional AI risk model |
| aTokens (Aave) | Fixed interest accrual | Risk-adjusted yield, halts when danger detected |
| stETH (Lido) | Staking rewards rebase | Autonomous de-risking before losses |
| Hypernative / Forta | Read-only risk dashboards | Autonomously **acts** on risk |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Smart Contracts | Solidity 0.8.24, Foundry |
| Risk Intelligence | Chainlink CRE (Confidential Compute + DON Consensus) |
| Cross-Chain | Chainlink CCIP (Hub-Spoke topology) |
| Access Control | OpenZeppelin AccessControlDefaultAdminRules |
| Token Standard | ERC-20 + ERC-677 + CCIP CCT |
| Frontend | Next.js + thirdweb v5 (Account Abstraction, gasless) |
| Testing | Forge (unit + fuzz + invariant), Slither, Certora |

## Roadmap

- [x] Architecture design + security audit (36 findings)
- [x] Phase 01 — Project setup + dependencies
- [x] Phase 02 — Layer 1 libraries (6 contracts, 47 tests)
- [ ] Phase 03 — Interfaces
- [ ] Phase 04 — Modules (PausableAC, CREReceiver, Fees, RiskEngine, RebaseExecutor, EventSentinel)
- [ ] Phase 05 — Core Token (share accounting, ERC-677, rebase)
- [ ] Phase 06 — Core Vault (ERC-4626, donation protection, risk-aware previews)
- [ ] Phase 07 — CCIP TokenPool (share-based bridging)
- [ ] Phase 08 — Hub + Spoke peers
- [ ] Phase 09 — CRE workflow YAML + simulation
- [ ] Phase 10 — Invariant tests + Slither
- [ ] Phase 11 — Certora formal verification
- [ ] Phase 12 — Frontend (Next.js + thirdweb)
- [ ] Phase 13 — Deployment + external audit

## Project Structure

```
oszillor/
├── contracts/
│   ├── src/
│   │   ├── libraries/      ← Pure logic (Layer 1)
│   │   ├── interfaces/     ← Contract boundaries (Layer 2)
│   │   ├── modules/        ← Reusable behaviors (Layer 3)
│   │   ├── core/           ← Token + Vault (Layer 4)
│   │   ├── peers/          ← CCIP orchestration (Layer 5)
│   │   └── adapters/       ← Risk plugins (Layer 6)
│   ├── test/
│   │   ├── unit/
│   │   ├── fuzz/
│   │   ├── invariant/
│   │   └── mocks/
│   ├── script/
│   ├── certora/
│   ├── foundry.toml
│   └── remappings.txt
├── cre-workflows/           ← CRE workflow YAML definitions
├── frontend/                ← Next.js + thirdweb dashboard
└── README.md
```

## License

MIT

---

<p align="center">
  <b>◈ OSZILLOR</b> — Built by <a href="https://github.com/vyqno">vyqno</a>
  <br>
  <i>The first protocol that de-risks before you get rekt.</i>
</p>
