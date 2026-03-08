/**
 * OSZILLOR Risk Intelligence API — Response Types
 */

/** Risk level tier matching Solidity enum */
export type RiskLevel = "SAFE" | "CAUTION" | "DANGER" | "CRITICAL"

/** GET /v1/risk/current response */
export type RiskCurrentResponse = {
  riskScore: number
  riskLevel: RiskLevel
  confidence: number
  timestamp: number
  reasoningHash: string
}

/** GET /v1/risk/portfolio response */
export type PortfolioResponse = {
  totalAssets: string
  emergencyMode: boolean
  allocations: Array<{
    protocol: string
    percentageBps: number
    apyBps: number
  }>
  strategy: {
    totalValueInEth: string
    ethBalance: string
    stableBalance: string
    currentEthPct: number
  }
}

/** GET /v1/risk/full response */
export type FullReportResponse = {
  risk: RiskCurrentResponse
  portfolio: PortfolioResponse
  generatedAt: string
}

/** POST /v1/alerts request body */
export type CreateAlertRequest = {
  subscriber: string
  condition: "RISK_ABOVE" | "RISK_BELOW" | "EMERGENCY"
  threshold: number
  webhookUrl: string
  ttlSeconds: number
}

/** POST /v1/alerts response */
export type CreateAlertResponse = {
  status: "submitted"
  ruleId: string
  subscriber: string
  condition: string
  threshold: number
  webhookUrl: string
  ttlSeconds: number
}

/** GET /v1/alerts/:id response */
export type AlertStatusResponse = {
  ruleId: number
  subscriber: string
  condition: string
  threshold: number
  webhookUrl: string
  createdAt: number
  ttl: number
  active: boolean
  expired: boolean
}
