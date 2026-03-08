/**
 * OSZILLOR Risk Intelligence API — Express Server
 *
 * x402 payment-gated API that exposes OSZILLOR's risk intelligence
 * to AI agents, DeFi protocols, and traders via micropayments.
 *
 * Architecture:
 *   - x402 middleware gates all /v1/* routes with USDC micropayments on Base Sepolia
 *   - Vault reader service reads on-chain state from Ethereum Sepolia (read-only)
 *   - Alert routes forward subscriptions to CRE W4 HTTP trigger
 *   - /health is free (no payment required)
 *
 * Usage:
 *   curl http://localhost:4021/health           # 200 OK (free)
 *   curl http://localhost:4021/v1/risk/current  # 402 Payment Required
 */
import express from "express"
import { paymentMiddleware, x402ResourceServer } from "@x402/express"
import { ExactEvmScheme } from "@x402/evm/exact/server"
import { HTTPFacilitatorClient } from "@x402/core/server"
import { config } from "./config"
import { healthRouter } from "./routes/health"
import { riskRouter } from "./routes/risk"
import { alertsRouter } from "./routes/alerts"

const app = express()
app.use(express.json())

// ──────────────────── x402 Payment Middleware ────────────────────

const facilitatorClient = new HTTPFacilitatorClient({
  url: config.facilitatorUrl,
})

const resourceServer = new x402ResourceServer(facilitatorClient)
  .register(config.network, new ExactEvmScheme())

const payTo = config.payToAddress

app.use(
  paymentMiddleware(
    {
      "GET /v1/risk/current": {
        accepts: [
          { scheme: "exact", price: "$0.001", network: config.network, payTo },
        ],
        description: "Current ETH risk score, level, and confidence from OSZILLOR CRE",
        mimeType: "application/json",
      },
      "GET /v1/risk/portfolio": {
        accepts: [
          { scheme: "exact", price: "$0.005", network: config.network, payTo },
        ],
        description: "Portfolio state: NAV, ETH/USDC allocation, strategy positions",
        mimeType: "application/json",
      },
      "GET /v1/risk/full": {
        accepts: [
          { scheme: "exact", price: "$0.01", network: config.network, payTo },
        ],
        description: "Full risk intelligence report: risk + portfolio + allocations",
        mimeType: "application/json",
      },
      "POST /v1/alerts": {
        accepts: [
          { scheme: "exact", price: "$0.01", network: config.network, payTo },
        ],
        description: "Create alert subscription via CRE W4 (RISK_ABOVE, RISK_BELOW, EMERGENCY)",
        mimeType: "application/json",
      },
      "GET /v1/alerts/:id": {
        accepts: [
          { scheme: "exact", price: "$0.001", network: config.network, payTo },
        ],
        description: "Check alert subscription status by rule ID",
        mimeType: "application/json",
      },
    },
    resourceServer,
  ),
)

// ──────────────────── Routes ────────────────────

app.use(healthRouter)  // Free — no x402
app.use(riskRouter)    // Gated — $0.001 to $0.01
app.use(alertsRouter)  // Gated — $0.001 to $0.01

// ──────────────────── Start ────────────────────

app.listen(config.port, () => {
  console.log(`
╔══════════════════════════════════════════════════════════╗
║  OSZILLOR Risk Intelligence API v1.0.0                  ║
║  x402-gated • Powered by Chainlink CRE                  ║
╠══════════════════════════════════════════════════════════╣
║  Server:    http://localhost:${config.port}                     ║
║  Network:   Base Sepolia (${config.network})              ║
║  Pay-to:    ${config.payToAddress.slice(0, 10)}...${config.payToAddress.slice(-4)}                        ║
╠══════════════════════════════════════════════════════════╣
║  Endpoints:                                              ║
║    GET  /health            FREE                          ║
║    GET  /v1/risk/current   $0.001 USDC                   ║
║    GET  /v1/risk/portfolio $0.005 USDC                   ║
║    GET  /v1/risk/full      $0.01  USDC                   ║
║    POST /v1/alerts         $0.01  USDC                   ║
║    GET  /v1/alerts/:id     $0.001 USDC                   ║
╚══════════════════════════════════════════════════════════╝
  `)
})

export { app }
