/**
 * OSZILLOR Risk Alerts — CRE Workflow W4
 *
 * Dual-trigger workflow for the x402 Risk Intelligence API:
 *   1. HTTP trigger: receives alert subscriptions from Express API → writes to AlertRegistry on Base Sepolia
 *   2. Cron trigger (60s): reads active rules from AlertRegistry (Base) + risk from OszillorVault (Eth Sepolia)
 *
 * This demonstrates cross-chain EVM reads within a single CRE workflow — a key CRE differentiator.
 */
import {
  CronCapability,
  HTTPCapability,
  EVMClient,
  handler,
  consensusMedianAggregation,
  Runner,
  type NodeRuntime,
  type Runtime,
  getNetwork,
  hexToBase64,
  bytesToHex,
} from "@chainlink/cre-sdk"
import {
  encodeAbiParameters,
  parseAbiParameters,
  encodeFunctionData,
  decodeFunctionResult,
  toHex,
} from "viem"
import { OszillorVault } from "../contracts/abi"
import type { Config, AlertRequest } from "./types"

// ──────────────────────────────────────────────────────────
//  HELPERS: ABI-encoded EVM reads via callContract
// ──────────────────────────────────────────────────────────

/** Encode a hex address to base64 for callContract (protobuf bytes JSON format) */
const addressToBase64 = (addr: string): string => {
  // Pad address to 20 bytes (40 hex chars) — standard EVM address
  const hex = addr.startsWith("0x") ? addr.slice(2) : addr
  return hexToBase64(`0x${hex.padStart(40, "0")}`)
}

/** Convert a hex calldata string to base64 for callContract data field */
const calldataToBase64 = (hex: string): string => {
  return hexToBase64(hex.startsWith("0x") ? hex : `0x${hex}`)
}

// ──────────────────────────────────────────────────────────
//  HTTP TRIGGER: Create Alert Subscription
// ──────────────────────────────────────────────────────────

/**
 * Handles HTTP trigger from the Express API.
 * Receives alert params, ABI-encodes them as AlertReport,
 * signs via CRE consensus, and writes to AlertRegistry on Base Sepolia.
 */
const onHttpTrigger = (runtime: Runtime<Config>, triggerOutput: { input: Uint8Array }): { ruleId: string; txHash: string } => {
  const config = runtime.config

  // Parse the HTTP trigger payload (JSON bytes from Express API)
  const bodyStr = new TextDecoder().decode(triggerOutput.input)
  const alert: AlertRequest = JSON.parse(bodyStr)

  runtime.log(`Alert subscription: ${alert.subscriber} condition=${alert.condition} threshold=${alert.threshold}`)

  // ABI-encode the AlertReport struct matching Solidity
  const reportData = encodeAbiParameters(
    parseAbiParameters(
      "address subscriber, uint8 condition, uint256 threshold, string webhookUrl, uint256 ttl"
    ),
    [
      alert.subscriber as `0x${string}`,
      alert.condition,
      BigInt(alert.threshold),
      alert.webhookUrl,
      BigInt(alert.ttl),
    ]
  )

  // Get Base Sepolia network
  const baseNetwork = getNetwork({
    chainFamily: "evm",
    chainSelectorName: config.alertEvm.chainName,
    isTestnet: config.alertEvm.chainName.includes("sepolia"),
  })

  if (!baseNetwork) {
    throw new Error(`Unknown chain: ${config.alertEvm.chainName}`)
  }

  // Sign the report via CRE DON consensus
  const reportResponse = runtime
    .report({
      encodedPayload: hexToBase64(reportData),
      encoderName: "evm",
      signingAlgo: "ecdsa",
      hashingAlgo: "keccak256",
    })
    .result()

  // Write to AlertRegistry on Base Sepolia
  const evmClient = new EVMClient(baseNetwork.chainSelector.selector)
  const writeResult = evmClient
    .writeReport(runtime, {
      receiver: config.alertEvm.alertRegistryAddress,
      report: reportResponse,
      gasConfig: {
        gasLimit: config.alertEvm.gasLimit,
      },
    })
    .result()

  const txHash = bytesToHex(writeResult.txHash || new Uint8Array(32))
  runtime.log(`Alert written to AlertRegistry: ${txHash}`)

  return { ruleId: "pending", txHash }
}

// ──────────────────────────────────────────────────────────
//  CRON TRIGGER: Evaluate Active Alert Rules
// ──────────────────────────────────────────────────────────

/**
 * Fetches current risk score from OszillorVault on Ethereum Sepolia.
 * Each DON node calls the contract independently, then consensus is reached.
 * Uses callContract (low-level EVM read) with ABI-encoded function selector.
 */
const fetchVaultState = (nodeRuntime: NodeRuntime<Config>): bigint => {
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: nodeRuntime.config.vaultEvm.chainName,
    isTestnet: nodeRuntime.config.vaultEvm.chainName.includes("sepolia"),
  })
  if (!network) return 0n

  const evmClient = new EVMClient(network.chainSelector.selector)

  // Read risk score
  const riskCalldata = encodeFunctionData({
    abi: OszillorVault,
    functionName: "currentRiskScore",
  })

  const riskReply = evmClient
    .callContract(nodeRuntime, {
      call: {
        to: addressToBase64(nodeRuntime.config.vaultEvm.vaultAddress),
        data: calldataToBase64(riskCalldata),
      },
    })
    .result()

  const replyHex = toHex(riskReply.data)
  if (!riskReply.data || riskReply.data.length === 0 || replyHex === "0x") {
    return 0n // Default risk score in simulation
  }

  const riskScore = decodeFunctionResult({
    abi: OszillorVault,
    functionName: "currentRiskScore",
    data: replyHex,
  }) as bigint

  return riskScore
}

/**
 * Evaluates alert rules against current vault state.
 * Cron runs every 60 seconds — reads from Ethereum Sepolia via DON consensus.
 *
 * Cross-chain flow:
 *   1. Node mode: Each DON node reads currentRiskScore from OszillorVault (Eth Sepolia)
 *   2. Consensus: Median aggregation ensures agreement on risk score
 *   3. Runtime: Evaluate alert conditions against the consensus risk score
 *
 * Note: AlertRegistry reads (Base Sepolia) will be added when the registry is deployed.
 * For now, alert rules would be provided via the HTTP trigger + on-chain storage.
 */
const onCronTrigger = (runtime: Runtime<Config>, _triggerOutput: unknown): { evaluated: number; triggered: number } => {
  // 1. Fetch risk score from Ethereum Sepolia via DON consensus
  const riskScore = runtime
    .runInNodeMode(fetchVaultState, consensusMedianAggregation())()
    .result()

  runtime.log(`Current risk score from Eth Sepolia: ${riskScore}`)

  // 2. Simple threshold evaluation (demonstrates cross-chain read)
  // In production, this would read active rules from AlertRegistry on Base Sepolia
  // and evaluate each rule against the fetched risk score.
  const defaultThreshold = 70n
  const isHighRisk = riskScore > defaultThreshold

  if (isHighRisk) {
    runtime.log(`HIGH RISK ALERT: score ${riskScore} exceeds threshold ${defaultThreshold}`)
  } else {
    runtime.log(`Risk normal: score ${riskScore} below threshold ${defaultThreshold}`)
  }

  return {
    evaluated: 1,
    triggered: isHighRisk ? 1 : 0,
  }
}

// ──────────────────────────────────────────────────────────
//  WORKFLOW INIT: Bind both triggers
// ──────────────────────────────────────────────────────────

const initWorkflow = (config: Config) => {
  const cron = new CronCapability()
  const httpTrigger = new HTTPCapability()

  return [
    handler(httpTrigger.trigger({ authorizedKeys: [] }), onHttpTrigger),
    handler(cron.trigger({ schedule: config.schedule }), onCronTrigger),
  ]
}

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
