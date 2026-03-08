/**
 * OSZILLOR Risk Intelligence — Lightweight x402 Fetch Demo
 *
 * Simple demo using @x402/fetch for automatic payment handling.
 * For the full AgentKit + LangChain agent, see: risk-api/agent/
 *
 * This script demonstrates the raw x402 payment flow without an LLM:
 *   1. Fetch current risk score         ($0.001 USDC)
 *   2. Fetch portfolio state            ($0.005 USDC)
 *   3. Create DANGER alert subscription ($0.01  USDC)
 *   4. Fetch full intelligence report   ($0.01  USDC)
 *   ─────────────────────────────────────────────
 *   Total cost: ~$0.026 USDC
 *
 * Prerequisites:
 *   - Risk API server running: `bun run dev` in risk-api/
 *   - EVM_PRIVATE_KEY env var set (Base Sepolia wallet with USDC)
 *
 * Usage:
 *   EVM_PRIVATE_KEY=0x... bun run demo/agent-demo.ts
 */
import { x402Client, wrapFetchWithPayment } from "@x402/fetch"
import { ExactEvmScheme } from "@x402/evm/exact/client"
import { privateKeyToAccount } from "viem/accounts"

const API_BASE = process.env.API_URL ?? "http://localhost:4021"

import { readFileSync, existsSync } from "fs"
import { homedir } from "os"
import * as readline from "readline"
import { Wallet } from "ethers"

// ──────────────────── Setup x402 Client ────────────────────

async function getSigner() {
  const envKey = process.env.EVM_PRIVATE_KEY as `0x${string}`
  if (envKey) return privateKeyToAccount(envKey)

  const keystorePath = `${homedir()}/.foundry/keystores/deployer`
  if (!existsSync(keystorePath)) {
    console.error("Error: EVM_PRIVATE_KEY not set and 'deployer' keystore not found.")
    process.exit(1)
  }

  console.log("EVM_PRIVATE_KEY not found. Using Foundry 'deployer' keystore...")
  
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  })

  // Prompt for password securely
  const password = await new Promise<string>((resolve) => {
    rl.question("Enter keystore password: ", (pass) => {
      rl.close()
      resolve(pass)
    })
  })

  try {
    const keystoreJson = readFileSync(keystorePath, "utf-8")
    console.log("  ... Keystore loaded. Decrypting... (takes 2-5s for scrypt)")
    const ethersWallet = Wallet.fromEncryptedJsonSync(keystoreJson, password)
    const pk = ethersWallet.privateKey as `0x${string}`
    console.log("  ✓ Decryption successful.")
    return privateKeyToAccount(pk)
  } catch (err) {
    console.error("  ✗ Failed to decrypt keystore. Incorrect password?")
    process.exit(1)
  }
}

// ──────────────────── Global State ────────────────────

let fetchWithPayment: any
let signer: ReturnType<typeof privateKeyToAccount>

async function setup() {
  signer = await getSigner()
  const client = new x402Client()
  
  // Register the EVM scheme. Cast to any if there's a minor viem version mismatch
  // in the expected Signer interface for x402 fetch.
  client.register("eip155:*", new ExactEvmScheme(signer as any))
  
  fetchWithPayment = wrapFetchWithPayment(fetch, client)
}

// ──────────────────── Helper ────────────────────

async function apiCall<T>(method: string, path: string, body?: object): Promise<T> {
  const url = `${API_BASE}${path}`
  console.log(`\n→ ${method} ${path}`)

  const options: RequestInit = {
    method,
    headers: { "Content-Type": "application/json" },
  }
  if (body) options.body = JSON.stringify(body)

  const response = await fetchWithPayment(url, options)

  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`)
  }

  const data = await response.json() as T
  console.log(`  ✓ ${response.status} OK`)
  return data
}

// ──────────────────── Agent Logic ────────────────────

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

async function main() {
  await setup()
  await sleep(1000) // Brief pause after setup

  console.log("╔══════════════════════════════════════════════════════════╗")
  console.log("║  OSZILLOR Risk Intelligence — AI Agent Demo             ║")
  console.log("║  x402 micropayments • Base Sepolia USDC                 ║")
  console.log("╚══════════════════════════════════════════════════════════╝")
  console.log(`\nAgent wallet: ${signer.address}`)
  console.log(`API endpoint: ${API_BASE}`)

  let totalCost = 0

  // ── Step 1: Fetch current risk score ($0.001) ──
  console.log("\n── Step 1: Current Risk Score ($0.001 USDC) ──")
  const risk = await apiCall<{
    riskScore: number
    riskLevel: string
    confidence: number
    timestamp: number
  }>("GET", "/v1/risk/current")
  console.log(`  Risk Score: ${risk.riskScore}/100 (${risk.riskLevel})`)
  console.log(`  Confidence: ${risk.confidence}%`)
  console.log(`  Updated:    ${new Date(risk.timestamp * 1000).toISOString()}`)
  totalCost += 0.001

  await sleep(3000) // Wait for facilitator to index payment before next step

  // ── Step 2: Fetch portfolio state ($0.005) ──
  console.log("\n── Step 2: Portfolio State ($0.005 USDC) ──")
  const portfolio = await apiCall<{
    totalAssets: string
    emergencyMode: boolean
    allocations: Array<{ protocol: string; percentageBps: number; apyBps: number }>
    strategy: { totalValueInEth: string; currentEthPct: number }
  }>("GET", "/v1/risk/portfolio")
  console.log(`  Total Assets:  ${portfolio.totalAssets} wei`)
  console.log(`  Emergency:     ${portfolio.emergencyMode}`)
  console.log(`  ETH Allocation: ${portfolio.strategy.currentEthPct / 100}%`)
  console.log(`  Allocations:`)
  for (const alloc of portfolio.allocations) {
    console.log(`    - ${alloc.protocol}: ${alloc.percentageBps / 100}% (APY: ${alloc.apyBps / 100}%)`)
  }
  totalCost += 0.005

  await sleep(3000) // Wait for facilitator to index payment before next step

  // ── Step 3: Create alert if risk is elevated ($0.01) ──
  console.log("\n── Step 3: Create Alert Subscription ($0.01 USDC) ──")
  const alert = await apiCall<{
    status: string
    condition: string
    threshold: number
  }>("POST", "/v1/alerts", {
    subscriber: signer.address,
    condition: "RISK_ABOVE",
    threshold: 70,
    webhookUrl: "https://agent.example.com/webhook/risk-alert",
    ttlSeconds: 86400, // 24 hours
  })
  console.log(`  Status:    ${alert.status}`)
  console.log(`  Condition: ${alert.condition} > ${alert.threshold}`)
  console.log(`  Duration:  24 hours`)
  totalCost += 0.01

  await sleep(3000) // Wait for facilitator to index payment before next step

  // ── Step 4: Fetch full intelligence report ($0.01) ──
  console.log("\n── Step 4: Full Intelligence Report ($0.01 USDC) ──")
  const full = await apiCall<{
    risk: { riskScore: number; riskLevel: string }
    portfolio: { totalAssets: string; emergencyMode: boolean }
    generatedAt: string
  }>("GET", "/v1/risk/full")
  console.log(`  Risk:       ${full.risk.riskScore} (${full.risk.riskLevel})`)
  console.log(`  Emergency:  ${full.portfolio.emergencyMode}`)
  console.log(`  Generated:  ${full.generatedAt}`)
  totalCost += 0.01

  // ── Summary ──
  console.log("\n══════════════════════════════════════════════════════════")
  console.log(`  Total x402 cost: $${totalCost.toFixed(3)} USDC`)
  console.log(`  Requests made:   4`)
  console.log(`  Agent decision:  ${risk.riskScore >= 70 ? "⚠ HIGH RISK — reduce exposure" : "✓ Risk acceptable — maintain positions"}`)
  console.log("══════════════════════════════════════════════════════════")
}

main().catch((err) => {
  console.error("Agent error:", err)
  process.exit(1)
})
