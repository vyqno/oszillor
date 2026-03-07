# OSZILLOR v2

Risk-adjusted yield protocol with Chainlink CRE, AI reasoning, privacy-preserving data access, and CCIP-ready cross-chain routing.

## One-line pitch

The first DeFi protocol that thinks for itself: AI-powered cross-chain yield intelligence, private risk engine, and autonomous hedging.

## Current status (as of 2026-03-06)

- Contracts compile successfully with Foundry (`make build`).
- Hub deployment to Sepolia is complete.
- Post-deploy operational roles were granted (`make roles`).
- W1 workflow upgrades are implemented:
  - Cross-chain yield scan from DefiLlama (`/pools`)
  - LLM-based risk + yield reasoning
  - ConfidentialHTTPClient for premium news signal
- Frontend dashboard exists with wallet connect, deposit/withdraw, risk gauge, position, and yield intelligence views.

## Track framing

- DeFi and Tokenization: cross-chain yield intelligence + autonomous vault allocation.
- Risk and Compliance: continuous risk scoring + circuit-breaker style emergency controls.
- CRE and AI: multi-source workflow compute + LLM reasoning.
- Privacy: ConfidentialHTTPClient for protected risk input pipeline.

## Why OSZILLOR is a superset of YieldCoin

| Dimension | YieldCoin pattern | OSZILLOR v2 |
| --- | --- | --- |
| Yield optimization | Cross-chain yield hunt | Cross-chain yield hunt + risk-adjusted allocation |
| AI | Recommendation layer | Recommendation layer + onchain report hash + deterministic fallback |
| Risk defense | Limited | 3-workflow defense-in-depth (W1/W2/W3) |
| Privacy | Not core | ConfidentialHTTPClient for proprietary risk/news inputs |
| Execution | Strategy-level | Strategy-level + autonomous hedge + rebase token mechanics |
| Capital efficiency | Atomic fund routing | Atomic fund routing with dynamic ETH/USDC hedging |
| Cross-chain rail | CCIP-style narrative | CCIP-ready hub/spoke contracts deployed in hub path |

## Upgrade plan progress (F-00 to F-07)

- [x] `F-00` Cross-chain yield intelligence in W1
- [x] `F-01` AI risk reasoning in W1
- [x] `F-02` ConfidentialHTTPClient in W1
- [x] `F-03` Sepolia hub deployment and role setup
- [x] `F-04` Frontend dashboard MVP (implemented)
- [ ] `F-04.1` Frontend polish and live-data UX
- [ ] `F-05` CRE simulation runbook execution against latest deployment
- [ ] `F-06` Demo video (3-4 minutes)
- [x] `F-07` README and submission structure refresh

## Architecture

### Contracts (hub path)

1. `MockLido` (Sepolia substitute for stETH)
2. `OszillorToken`
3. `RiskEngine` (W1 receiver)
4. `RebaseExecutor` (W3 receiver)
5. `EventSentinel` (W2 receiver)
6. `VaultStrategy`
7. `OszillorVault`
8. `OszillorTokenPool`
9. `HubPeer`

### V2 Fund Flow (Atomic Routing)

Unlike earlier versions where capital might sit idle in the vault awaiting a rebalance, v2 implements "Atomic Fund Routing" directly on user actions:
- **Deposit**: When a user deposits WETH into `OszillorVault`, the vault instantly transfers the assets to `VaultStrategy` and stakes them (e.g., into Lido). Yield generation begins in the same block.
- **Withdraw**: When a user withdraws, the Vault calls an internal `_ensureLiquidity()` method that pulls funds back via `strategy.withdrawToVault()`, automatically unstaking from Lido if the strategy lacks idle WETH.

### CRE workflows

- `W1 Risk Scanner` (`*/30s`): multi-signal risk scoring + cross-chain yield scan + AI reasoning.
- `W2 Event Sentinel` (`*/15s`): fast anomaly/threat checks and emergency signal path.
- `W3 Rebase Executor` (`*/300s`): computes and applies rebase/position updates.

### CRE capability coverage

- Cron Trigger
- HTTPClient (CoinGecko)
- HTTPClient (DefiLlama chains)
- HTTPClient (DefiLlama yields)
- ConfidentialHTTPClient (premium news)
- HTTPClient to LLM API
- Compute
- DON consensus
- EVM read
- EVM write

## Sepolia deployment (hub)

Deployment completed with `DeployHub.s.sol` and `SetupRoles.s.sol`.

| Contract | Address |
| --- | --- |
| OszillorToken | `0xe14590980844A4A58aCAf7e8B22cBb36357772eF` |
| MockLido | `0x44a64cf4282AaFb70E87E11F04aaD711242e42D1` |
| VaultStrategy | `0xf994E4aD3C62F05BCa67cDE4010066fA96200212` |
| RiskEngine | `0x39EcdbD6550E1EC7f99c2a7D0927E1E5B88b91CE` |
| RebaseExecutor | `0x16e4A4Af28ECA70fF2fD8401610E770976F17368` |
| EventSentinel | `0x236fd9ebEF2F7fFba47034F5a3907B32CdF696F3` |
| OszillorVault | `0xe275f81598634329E2e32d24b6ba1B51E3e368F1` |
| OszillorTokenPool | `0x19465b9456492760859Cb16501723Fd870d13E16` |
| HubPeer | `0x698E21b82ACF93189731AF81f906991fCEBB02Bd` |

## Important operational follow-up (not optional)

After `make roles`, complete admin hardening:

1. `vault.beginDefaultAdminTransfer(multisig)`
2. `token.beginDefaultAdminTransfer(multisig)`
3. Wait 5 days (AccessControlDefaultAdminRules delay)
4. Multisig calls `acceptDefaultAdminTransfer()` on both
5. Deployer renounces privileged roles

## What is still left to finish

1. Run `make validate` on current Sepolia deployment and archive output.
2. Run all 3 CRE simulations against current staging configs and capture logs.
3. Run live deposit/withdraw smoke flow from frontend against Sepolia.
4. Complete frontend polish for demo recording:
   - Replace placeholder AI text where possible (or clearly label as deterministic demo output)
   - Ensure event timeline reflects live contract/workflow events
5. Record final 3-4 minute demo video.
6. Finalize submission package (README, architecture diagram, video, track mapping).

## Local development

### Prerequisites

- Foundry (`forge`, `cast`)
- Bun (for CRE workflow tests)
- Node.js 18+

### Build and test

```bash
make build
make test
cd cre-workflows/tests && bun test
```

### Deploy hub

```bash
make deploy-hub
make roles
make validate
```

### Simulate workflows

```bash
cd cre-workflows
cre workflow simulate ./oszillor-risk-scanner --target staging-settings
cre workflow simulate ./oszillor-event-sentinel --target staging-settings
cre workflow simulate ./oszillor-rebase-executor --target staging-settings
```

## Frontend

Path: `frontend/`

Tech stack:
- Next.js 14
- Tailwind
- wagmi + viem
- RainbowKit
- recharts + framer-motion

Run:

```bash
cd frontend
npm install
npm run dev
```

Expected env vars (`frontend/.env.local`):

```bash
NEXT_PUBLIC_VAULT_ADDRESS=0xe275f81598634329E2e32d24b6ba1B51E3e368F1
NEXT_PUBLIC_TOKEN_ADDRESS=0xe14590980844A4A58aCAf7e8B22cBb36357772eF
NEXT_PUBLIC_STRATEGY_ADDRESS=0xf994E4aD3C62F05BCa67cDE4010066fA96200212
NEXT_PUBLIC_WETH_ADDRESS=0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=YOUR_PROJECT_ID
```

## Repository map

```text
contracts/
  src/
  script/deploy/
  script/interactions/
  test/

cre-workflows/
  oszillor-risk-scanner/
  oszillor-event-sentinel/
  oszillor-rebase-executor/
  tests/

frontend/
  app/
  components/
  hooks/
  lib/
```

## Plan reference

Primary implementation plan source:
- `.references/2026-03-06-implement-the-following-plan.txt`

This README reflects that plan plus the completed Sepolia hub deployment and post-deploy role setup.
