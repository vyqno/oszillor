/**
 * GET /health — Free health check endpoint
 */
import { Router } from "express"

const router = Router()
const startedAt = Date.now()

router.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "oszillor-risk-intelligence-api",
    version: "1.0.0",
    uptime: Math.floor((Date.now() - startedAt) / 1000),
    timestamp: new Date().toISOString(),
  })
})

export { router as healthRouter }
