/**
 * OSZILLOR Risk Intelligence API — Risk Formatter Service
 *
 * Transforms raw on-chain data (bigint) into JSON-friendly response objects.
 */
import type {
  RiskCurrentResponse,
  PortfolioResponse,
  FullReportResponse,
  RiskLevel,
} from "../types"
import type { RiskState, Allocation, StrategyState } from "./vault-reader"

/** Maps a 0-100 risk score to a human-readable tier */
export function toRiskLevel(score: number): RiskLevel {
  if (score >= 90) return "CRITICAL"
  if (score >= 70) return "DANGER"
  if (score >= 40) return "CAUTION"
  return "SAFE"
}

/** Formats the /v1/risk/current response */
export function formatRiskCurrent(riskState: RiskState): RiskCurrentResponse {
  const score = Number(riskState.riskScore)
  return {
    riskScore: score,
    riskLevel: toRiskLevel(score),
    confidence: Number(riskState.confidence),
    timestamp: Number(riskState.timestamp),
    reasoningHash: riskState.reasoningHash,
  }
}

/** Formats the /v1/risk/portfolio response */
export function formatPortfolio(
  totalAssets: bigint,
  emergencyMode: boolean,
  allocations: Allocation[],
  strategy: StrategyState
): PortfolioResponse {
  return {
    totalAssets: totalAssets.toString(),
    emergencyMode,
    allocations: allocations.map((a) => ({
      protocol: a.protocol,
      percentageBps: Number(a.percentageBps),
      apyBps: Number(a.apyBps),
    })),
    strategy: {
      totalValueInEth: strategy.totalValueInEth.toString(),
      ethBalance: strategy.ethBalance.toString(),
      stableBalance: strategy.stableBalance.toString(),
      currentEthPct: Number(strategy.currentEthPct),
    },
  }
}

/** Formats the /v1/risk/full response */
export function formatFullReport(
  risk: RiskCurrentResponse,
  portfolio: PortfolioResponse
): FullReportResponse {
  return {
    risk,
    portfolio,
    generatedAt: new Date().toISOString(),
  }
}
