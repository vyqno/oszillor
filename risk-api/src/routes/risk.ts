/**
 * Risk data endpoints — all x402 payment-gated
 *
 * GET /v1/risk/current    ($0.001) — Current risk score + level + confidence
 * GET /v1/risk/portfolio   ($0.005) — NAV, allocations, strategy state
 * GET /v1/risk/full        ($0.01)  — Combined risk + portfolio report
 */
import { Router } from "express"
import {
  readRiskState,
  readTotalAssets,
  readEmergencyMode,
  readAllocations,
  readStrategyState,
} from "../services/vault-reader"
import {
  formatRiskCurrent,
  formatPortfolio,
  formatFullReport,
} from "../services/risk-formatter"

const router = Router()

// GET /v1/risk/current — $0.001 USDC
router.get("/v1/risk/current", async (_req, res) => {
  try {
    const riskState = await readRiskState()
    res.json(formatRiskCurrent(riskState))
  } catch (error) {
    console.error("Error reading risk state:", error)
    res.status(503).json({ error: "Failed to read vault state" })
  }
})

// GET /v1/risk/portfolio — $0.005 USDC
router.get("/v1/risk/portfolio", async (_req, res) => {
  try {
    const [totalAssets, emergencyMode, allocations, strategy] = await Promise.all([
      readTotalAssets(),
      readEmergencyMode(),
      readAllocations(),
      readStrategyState(),
    ])
    res.json(formatPortfolio(totalAssets, emergencyMode, allocations, strategy))
  } catch (error) {
    console.error("Error reading portfolio:", error)
    res.status(503).json({ error: "Failed to read vault state" })
  }
})

// GET /v1/risk/full — $0.01 USDC
router.get("/v1/risk/full", async (_req, res) => {
  try {
    const [riskState, totalAssets, emergencyMode, allocations, strategy] = await Promise.all([
      readRiskState(),
      readTotalAssets(),
      readEmergencyMode(),
      readAllocations(),
      readStrategyState(),
    ])
    const risk = formatRiskCurrent(riskState)
    const portfolio = formatPortfolio(totalAssets, emergencyMode, allocations, strategy)
    res.json(formatFullReport(risk, portfolio))
  } catch (error) {
    console.error("Error reading full report:", error)
    res.status(503).json({ error: "Failed to read vault state" })
  }
})

export { router as riskRouter }
