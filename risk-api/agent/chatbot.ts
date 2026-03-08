/**
 * OSZILLOR Risk Intelligence Agent — Interactive Chat Mode
 *
 * A real Coinbase AgentKit agent that:
 *   1. Has a CDP-managed wallet on Base Sepolia
 *   2. Uses x402ActionProvider to discover and pay for OSZILLOR risk data
 *   3. Uses LangChain ReAct agent (Claude Sonnet) to reason about risk intelligence
 *   4. Can autonomously decide to create alert subscriptions based on risk levels
 *
 * This is the official Coinbase agent pattern — AgentKit + LangChain + x402.
 *
 * Usage:
 *   cp .env.example .env  # Fill in credentials
 *   bun run start         # Interactive chat mode
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
import * as readline from "readline"

dotenv.config()

// ──────────────────── Validation ────────────────────

function validateEnvironment(): void {
  const required = ["ANTHROPIC_API_KEY", "CDP_API_KEY_ID", "CDP_API_KEY_SECRET", "CDP_WALLET_SECRET"]
  const missing = required.filter((v) => !process.env[v])

  if (missing.length > 0) {
    console.error("Missing required environment variables:")
    missing.forEach((v) => console.error(`  ${v}=your_${v.toLowerCase()}_here`))
    console.error("\nSee .env.example for details.")
    process.exit(1)
  }
}

validateEnvironment()

// ──────────────────── Configuration ────────────────────

const RISK_API_URL = process.env.RISK_API_URL ?? "http://localhost:4021"

const SYSTEM_PROMPT = `
You are the OSZILLOR Risk Intelligence Agent — an autonomous AI agent that monitors ETH risk
data from the OSZILLOR protocol and makes risk-informed decisions.

You have access to a crypto wallet on Base Sepolia and can pay for risk intelligence data
using x402 micropayments (USDC). Your primary data source is the OSZILLOR Risk Intelligence API.

OSZILLOR API Endpoints (all x402-gated):
  GET  ${RISK_API_URL}/v1/risk/current    — Current risk score, level, confidence ($0.001 USDC)
  GET  ${RISK_API_URL}/v1/risk/portfolio   — Portfolio: NAV, ETH/USDC allocation, strategy ($0.005 USDC)
  GET  ${RISK_API_URL}/v1/risk/full        — Full report: risk + portfolio combined ($0.01 USDC)
  POST ${RISK_API_URL}/v1/alerts           — Create alert subscription ($0.01 USDC)
  GET  ${RISK_API_URL}/v1/alerts/:id       — Check alert status ($0.001 USDC)
  GET  ${RISK_API_URL}/health              — Health check (free)

Risk Levels: SAFE (0-39), CAUTION (40-69), DANGER (70-89), CRITICAL (90-100)

Your workflow:
1. When asked about risk, first check the health endpoint (free), then fetch risk data (paid)
2. When the risk level is DANGER or CRITICAL, recommend creating an alert subscription
3. For alerts, POST to /v1/alerts with body: { subscriber: "<your wallet>", condition: "RISK_ABOVE", threshold: 70, webhookUrl: "https://agent.example.com/webhook", ttlSeconds: 86400 }
4. Always report your total x402 spending to the user
5. If you get a 402 response, use retry_http_request_with_x402 to pay and retry

Be concise, data-driven, and always explain what the risk data means for ETH holders.
`

// ──────────────────── Agent Init ────────────────────

async function initializeAgent() {
  // Initialize LLM
  const llm = new ChatAnthropic({ model: "claude-sonnet-4-5-20250929" })

  // Configure CDP Wallet Provider (managed wallet — no raw private keys)
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

  // x402 configuration — register OSZILLOR Risk API as an approved service
  const x402Config = {
    registeredServices: [RISK_API_URL],
    allowDynamicServiceRegistration: false,
    maxPaymentUsdc: 1.0,
  }

  // Action providers — wallet + x402 + ERC20 (for checking USDC balance)
  const actionProviders = [
    walletActionProvider(),
    cdpApiActionProvider(),
    cdpEvmWalletActionProvider(),
    erc20ActionProvider(),
    x402ActionProvider(x402Config),
  ]

  // Initialize AgentKit
  const agentkit = await AgentKit.from({
    walletProvider,
    actionProviders,
  })

  const tools = await getLangChainTools(agentkit)
  console.log(`Loaded ${tools.length} tools`)

  // LangChain ReAct agent with memory
  const memory = new MemorySaver()
  const agentConfig = { configurable: { thread_id: "oszillor-risk-agent" } }

  const agent = createReactAgent({
    llm,
    tools,
    checkpointSaver: memory,
    messageModifier: SYSTEM_PROMPT,
  })

  return { agent, config: agentConfig }
}

// ──────────────────── Chat Loop ────────────────────

async function runChatMode(agent: any, config: any) {
  console.log("\n────────────────────────────────────────────────────")
  console.log("  OSZILLOR Risk Intelligence Agent — Chat Mode")
  console.log("  Type your questions. Type 'exit' to quit.")
  console.log("────────────────────────────────────────────────────\n")

  console.log("Try these prompts:")
  console.log("  • 'Check the current ETH risk level'")
  console.log("  • 'Get the full portfolio report'")
  console.log("  • 'Create an alert if risk goes above 70'")
  console.log("  • 'What is my USDC balance?'")
  console.log()

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  })

  const question = (prompt: string): Promise<string> =>
    new Promise((resolve) => rl.question(prompt, resolve))

  try {
    while (true) {
      const userInput = await question("\nYou: ")

      if (userInput.toLowerCase() === "exit") {
        break
      }

      if (!userInput.trim()) continue

      const stream = await agent.stream(
        { messages: [new HumanMessage(userInput)] },
        config,
      )

      for await (const chunk of stream) {
        if ("agent" in chunk) {
          const content = chunk.agent.messages[0].content
          if (content) console.log(`\nAgent: ${content}`)
        } else if ("tools" in chunk) {
          const content = chunk.tools.messages[0].content
          if (content) {
            // Truncate verbose tool output
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
  } finally {
    rl.close()
    console.log("\nAgent shutting down.")
  }
}

// ──────────────────── Entry Point ────────────────────

async function main() {
  console.log("\n╔══════════════════════════════════════════════════════════╗")
  console.log("║  OSZILLOR Risk Intelligence Agent                       ║")
  console.log("║  Coinbase AgentKit + LangChain + Claude + x402           ║")
  console.log("╚══════════════════════════════════════════════════════════╝\n")

  const { agent, config } = await initializeAgent()
  await runChatMode(agent, config)
}

main().catch((err) => {
  console.error("Fatal error:", err)
  process.exit(1)
})
