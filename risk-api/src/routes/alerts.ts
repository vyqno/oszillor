/**
 * Alert subscription endpoints — x402 payment-gated
 *
 * POST /v1/alerts       ($0.01)  — Create alert subscription (via CRE W4 HTTP trigger)
 * GET  /v1/alerts/:id   ($0.001) — Check alert subscription status
 */
import { Router } from "express"
import { createPublicClient, http } from "viem"
import { baseSepolia } from "viem/chains"
import { config } from "../config"
import type { CreateAlertRequest, CreateAlertResponse, AlertStatusResponse } from "../types"

const ALERT_REGISTRY_ABI = [
  {
    inputs: [{ name: "ruleId", type: "uint256" }],
    name: "getRule",
    outputs: [
      {
        components: [
          { name: "subscriber", type: "address" },
          { name: "condition", type: "uint8" },
          { name: "threshold", type: "uint256" },
          { name: "webhookUrl", type: "string" },
          { name: "createdAt", type: "uint256" },
          { name: "ttl", type: "uint256" },
          { name: "active", type: "bool" },
        ],
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "ruleId", type: "uint256" }],
    name: "isRuleActive",
    outputs: [{ type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
] as const

const CONDITION_MAP: Record<string, number> = {
  RISK_ABOVE: 0,
  RISK_BELOW: 1,
  EMERGENCY: 2,
}

const CONDITION_NAMES: Record<number, string> = {
  0: "RISK_ABOVE",
  1: "RISK_BELOW",
  2: "EMERGENCY",
}

let _baseClient: ReturnType<typeof createPublicClient> | null = null

function getBaseClient() {
  if (!_baseClient) {
    _baseClient = createPublicClient({
      chain: baseSepolia,
      transport: http(config.baseSepoliaRpc),
    })
  }
  return _baseClient
}

const router = Router()

// POST /v1/alerts — $0.01 USDC
router.post("/v1/alerts", async (req, res) => {
  try {
    const body = req.body as CreateAlertRequest

    // Validate required fields
    if (!body.subscriber || !body.condition || !body.webhookUrl) {
      res.status(400).json({ error: "Missing required fields: subscriber, condition, webhookUrl" })
      return
    }

    const conditionNum = CONDITION_MAP[body.condition]
    if (conditionNum === undefined) {
      res.status(400).json({ error: "Invalid condition. Use: RISK_ABOVE, RISK_BELOW, or EMERGENCY" })
      return
    }

    if (body.condition !== "EMERGENCY" && (body.threshold < 0 || body.threshold > 100)) {
      res.status(400).json({ error: "Threshold must be 0-100 for risk-based conditions" })
      return
    }

    // Forward to CRE W4 HTTP trigger (if configured)
    if (config.creW4TriggerUrl) {
      try {
        await fetch(config.creW4TriggerUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            subscriber: body.subscriber,
            condition: conditionNum,
            threshold: body.threshold ?? 0,
            webhookUrl: body.webhookUrl,
            ttl: body.ttlSeconds ?? 3600,
          }),
        })
      } catch (err) {
        console.error("Failed to forward to CRE W4:", err)
        // Don't fail the request — CRE trigger may not be deployed yet
      }
    }

    const response: CreateAlertResponse = {
      status: "submitted",
      ruleId: "pending",
      subscriber: body.subscriber,
      condition: body.condition,
      threshold: body.threshold ?? 0,
      webhookUrl: body.webhookUrl,
      ttlSeconds: body.ttlSeconds ?? 3600,
    }

    res.status(201).json(response)
  } catch (error) {
    console.error("Error creating alert:", error)
    res.status(500).json({ error: "Failed to create alert subscription" })
  }
})

// GET /v1/alerts/:id — $0.001 USDC
router.get("/v1/alerts/:id", async (req, res) => {
  try {
    const ruleId = BigInt(req.params.id)
    const client = getBaseClient()

    const [rule, isActive] = await Promise.all([
      client.readContract({
        address: config.alertRegistryAddress,
        abi: ALERT_REGISTRY_ABI,
        functionName: "getRule",
        args: [ruleId],
      }),
      client.readContract({
        address: config.alertRegistryAddress,
        abi: ALERT_REGISTRY_ABI,
        functionName: "isRuleActive",
        args: [ruleId],
      }),
    ])

    const typedRule = rule as {
      subscriber: `0x${string}`
      condition: number
      threshold: bigint
      webhookUrl: string
      createdAt: bigint
      ttl: bigint
      active: boolean
    }

    const response: AlertStatusResponse = {
      ruleId: Number(ruleId),
      subscriber: typedRule.subscriber,
      condition: CONDITION_NAMES[typedRule.condition] ?? "UNKNOWN",
      threshold: Number(typedRule.threshold),
      webhookUrl: typedRule.webhookUrl,
      createdAt: Number(typedRule.createdAt),
      ttl: Number(typedRule.ttl),
      active: typedRule.active,
      expired: !isActive && typedRule.active,
    }

    res.json(response)
  } catch (error) {
    console.error("Error reading alert:", error)
    res.status(404).json({ error: "Alert rule not found" })
  }
})

export { router as alertsRouter }
