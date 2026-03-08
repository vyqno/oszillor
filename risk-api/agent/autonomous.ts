/**
 * OSZILLOR Risk Intelligence Agent — Autonomous Mode
 *
 * Runs the agent in a loop without human interaction. The LLM decides what to do:
 *   1. Check wallet USDC balance
 *   2. Fetch current risk score (pays $0.001 USDC via x402)
 *   3. Analyze the risk level
 *   4. If DANGER/CRITICAL: fetch full report ($0.01) and create alert ($0.01)
 *   5. Report findings and total spending
 *
 * This demonstrates true autonomous AI agent behavior — machine-to-machine
 * commerce via x402 micropayments without any human in the loop.
 *
 * Usage:
 *   cp .env.example .env  # Fill in credentials
 *   bun run auto          # Autonomous mode
 */
import {
  AgentKit,
  CdpEvmWalletProvider,
  walletActionProvider,
  erc20ActionProvider,
  cdpApiActionProvider,
  cdpEvmWalletActionProvider,
  x402ActionProvider,
} from "@coinbase/agentkit"
import { getLangChainTools } from "@coinbase/agentkit-langchain"
import { HumanMessage } from "@langchain/core/messages"
import { MemorySaver } from "@langchain/langgraph"
import { createReactAgent } from "@langchain/langgraph/prebuilt"
import { ChatAnthropic } from "@langchain/anthropic"
import * as dotenv from "dotenv"

dotenv.config()

// ──────────────────── Validation ────────────────────

function validateEnvironment(): void {
  const required = ["ANTHROPIC_API_KEY", "CDP_API_KEY_ID", "CDP_API_KEY_SECRET", "CDP_WALLET_SECRET"]
  const missing = required.filter((v) => !process.env[v])

  if (missing.length > 0) {
    console.error("Missing required environment variables:")
    missing.forEach((v) => console.error(`  ${v}=your_${v.toLowerCase()}_here`))
    process.exit(1)
  }
}

validateEnvironment()

// ──────────────────── Configuration ────────────────────

const RISK_API_URL = process.env.RISK_API_URL ?? "http://localhost:4021"

const SYSTEM_PROMPT = `
You are the OSZILLOR Risk Intelligence Agent operating in AUTONOMOUS mode.
You have a CDP wallet on Base Sepolia with USDC for x402 micropayments.

Your mission: Monitor OSZILLOR ETH risk intelligence and take protective actions.

OSZILLOR Risk API (x402-gated):
  GET  ${RISK_API_URL}/health              — Free health check
  GET  ${RISK_API_URL}/v1/risk/current     — Risk score + level ($0.001 USDC)
  GET  ${RISK_API_URL}/v1/risk/portfolio   — Portfolio state ($0.005 USDC)
  GET  ${RISK_API_URL}/v1/risk/full        — Full report ($0.01 USDC)
  POST ${RISK_API_URL}/v1/alerts           — Create alert ($0.01 USDC)

Risk tiers: SAFE (0-39), CAUTION (40-69), DANGER (70-89), CRITICAL (90-100)

AUTONOMOUS PROTOCOL:
1. First, check ${RISK_API_URL}/health (free) to verify the API is online
2. Fetch current risk score from ${RISK_API_URL}/v1/risk/current (costs $0.001 USDC)
3. Analyze the response:
   - If SAFE: Report status. No further action needed.
   - If CAUTION: Fetch full report from ${RISK_API_URL}/v1/risk/full ($0.01 USDC) for deeper analysis
   - If DANGER or CRITICAL: Fetch full report AND create an alert subscription
4. For creating alerts, POST to ${RISK_API_URL}/v1/alerts with:
   { "subscriber": "<your wallet address>", "condition": "RISK_ABOVE", "threshold": 70, "webhookUrl": "https://agent.oszillor.xyz/webhook/autonomous", "ttlSeconds": 86400 }
5. Summarize: risk level, key data points, actions taken, and total USDC spent

When you encounter a 402 Payment Required, pay using retry_http_request_with_x402.
Always be cost-conscious — don't fetch data you don't need.
After completing your analysis, end with "AUTONOMOUS CYCLE COMPLETE".
`

// ──────────────────── Agent Init ────────────────────

async function initializeAgent() {
  const llm = new ChatAnthropic({ model: "claude-sonnet-4-5-20250929" })

  const walletProvider = await CdpEvmWalletProvider.configureWithWallet({
    apiKeyId: process.env.CDP_API_KEY_ID,
    apiKeySecret: process.env.CDP_API_KEY_SECRET,
    walletSecret: process.env.CDP_WALLET_SECRET,
    idempotencyKey: process.env.IDEMPOTENCY_KEY,
    address: process.env.ADDRESS as `0x${string}` | undefined,
    networkId: process.env.NETWORK_ID ?? "base-sepolia",
  })

  console.log(`Agent wallet: ${walletProvider.getAddress()}`)
  console.log(`Network:      ${walletProvider.getNetwork().networkId}`)

  const x402Config = {
    registeredServices: [RISK_API_URL],
    allowDynamicServiceRegistration: false,
    maxPaymentUsdc: 1.0,
  }

  const actionProviders = [
    walletActionProvider(),
    cdpApiActionProvider(),
    cdpEvmWalletActionProvider(),
    erc20ActionProvider(),
    x402ActionProvider(x402Config),
  ]

  const agentkit = await AgentKit.from({
    walletProvider,
    actionProviders,
  })

  const tools = await getLangChainTools(agentkit)
  const memory = new MemorySaver()
  const agentConfig = { configurable: { thread_id: "oszillor-autonomous-agent" } }

  const agent = createReactAgent({
    llm,
    tools,
    checkpointSaver: memory,
    messageModifier: SYSTEM_PROMPT,
  })

  return { agent, config: agentConfig }
}

// ──────────────────── Autonomous Execution ────────────────────

async function runAutonomousCycle(agent: any, config: any) {
  console.log("\n── Autonomous Risk Assessment Cycle ──\n")

  const prompt = `
Execute your autonomous risk monitoring protocol now.
Start by checking the OSZILLOR Risk API health, then fetch and analyze the current risk state.
Take appropriate actions based on the risk level. Report your findings and spending.
  `.trim()

  const stream = await agent.stream(
    { messages: [new HumanMessage(prompt)] },
    config,
  )

  for await (const chunk of stream) {
    if ("agent" in chunk) {
      const content = chunk.agent.messages[0].content
      if (content) console.log(`\nAgent: ${content}`)
    } else if ("tools" in chunk) {
      const content = chunk.tools.messages[0].content
      if (content) {
        const text = typeof content === "string" ? content : JSON.stringify(content)
        if (text.length > 500) {
          console.log(`  [Tool] ${text.substring(0, 500)}...`)
        } else {
          console.log(`  [Tool] ${text}`)
        }
      }
    }
  }
}

// ──────────────────── Entry Point ────────────────────

async function main() {
  console.log("\n╔══════════════════════════════════════════════════════════╗")
  console.log("║  OSZILLOR Risk Agent — Autonomous Mode                  ║")
  console.log("║  AgentKit + Claude Sonnet + x402 Micropayments           ║")
  console.log("╚══════════════════════════════════════════════════════════╝\n")

  const { agent, config } = await initializeAgent()

  // Run one autonomous cycle
  await runAutonomousCycle(agent, config)

  console.log("\n── Autonomous cycle finished ──")
}

main().catch((err) => {
  console.error("Fatal error:", err)
  process.exit(1)
})
