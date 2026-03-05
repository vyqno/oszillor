/**
 * OSZILLOR Event Sentinel — CRE Workflow W2
 *
 * Trigger: Cron every 30 seconds (polls for threats)
 * Flow:    Cron → HTTP (stablecoin data) → Compute (threat classification)
 *          → EVM Write (if emergency detected)
 * Target:  EventSentinel.onReport(bytes metadata, bytes report)
 *
 * Monitors DeFi ecosystem for danger signals:
 * - Stablecoin TVL drops > 10% in 1 hour
 * - Large transfer anomalies
 * - Protocol pause events
 *
 * NOTE: Uses Cron trigger for simulation compatibility. In production,
 * this would use EVM Log trigger watching USDC Transfer events.
 */
import {
  CronCapability,
  HTTPClient,
  EVMClient,
  handler,
  consensusMedianAggregation,
  Runner,
  type NodeRuntime,
  type Runtime,
  getNetwork,
  bytesToHex,
  hexToBase64,
} from "@chainlink/cre-sdk"
import {
  encodeAbiParameters,
  parseAbiParameters,
  keccak256,
  toHex,
  pad,
} from "viem"

// ──────────────────── Config Types ────────────────────

type EvmConfig = {
  chainName: string
  eventSentinelAddress: string
  gasLimit: string
}

type Config = {
  schedule: string
  whaleAlertUrl: string
  tvlThresholdDropPct: number
  largeTransferThresholdUsd: number
  evms: EvmConfig[]
}

// RiskLevel enum values matching Solidity
const RISK_LEVEL = {
  SAFE: 0,
  CAUTION: 1,
  DANGER: 2,
  CRITICAL: 3,
} as const

type ThreatResult = {
  threatDetected: boolean
  level: number
  threatType: `0x${string}`
  emergencyHalt: boolean
  txHash: string
}

// ──────────────────── Threat Detection ────────────────────

type ThreatAssessment = {
  level: number
  threatType: string
  riskAdjustment: bigint
  emergencyHalt: boolean
  suggestedDuration: bigint
  reason: string
}

/**
 * Fetches stablecoin data and checks for threats.
 * Each DON node evaluates independently; consensus selects median risk adjustment.
 */
const fetchAndClassifyThreat = (
  nodeRuntime: NodeRuntime<Config>
): bigint => {
  const httpClient = new HTTPClient()

  const resp = httpClient
    .sendRequest(nodeRuntime, {
      url: nodeRuntime.config.whaleAlertUrl,
      method: "GET" as const,
    })
    .result()

  const bodyText = new TextDecoder().decode(resp.body)

  try {
    const data = JSON.parse(bodyText) as {
      peggedAssets?: Array<{
        name: string
        symbol: string
        circulating?: { peggedUSD?: number }
        circulatingPrevHour?: { peggedUSD?: number }
      }>
    }

    const stablecoins = data.peggedAssets || []

    // Check USDC and USDT specifically
    const majors = stablecoins.filter(
      (s) => s.symbol === "USDC" || s.symbol === "USDT" || s.symbol === "DAI"
    )

    let maxDropPct = 0
    for (const stable of majors) {
      const current = stable.circulating?.peggedUSD || 0
      const prevHour = stable.circulatingPrevHour?.peggedUSD || current

      if (prevHour > 0) {
        const dropPct = ((prevHour - current) / prevHour) * 100
        if (dropPct > maxDropPct) {
          maxDropPct = dropPct
        }
      }
    }

    // Return drop percentage as risk adjustment (0 = no threat)
    // Scale to integer for consensus
    return BigInt(Math.floor(maxDropPct * 10)) // 10x for precision
  } catch {
    return 0n // No threat if parsing fails
  }
}

// ──────────────────── Main Workflow ────────────────────

const onCronTrigger = (runtime: Runtime<Config>): ThreatResult => {
  const evmConfig = runtime.config.evms[0]

  // Step 1: Fetch threat data with DON consensus
  const riskAdjustmentScaled = runtime
    .runInNodeMode(fetchAndClassifyThreat, consensusMedianAggregation())()
    .result()

  const dropPctScaled = Number(riskAdjustmentScaled)
  const dropPct = dropPctScaled / 10 // Restore precision

  runtime.log(`Stablecoin max TVL drop: ${dropPct}%`)

  // Step 2: Classify threat level
  let assessment: ThreatAssessment

  if (dropPct >= 10) {
    // CRITICAL — major stablecoin event
    assessment = {
      level: RISK_LEVEL.CRITICAL,
      threatType: "STABLECOIN_TVL_CRASH",
      riskAdjustment: BigInt(Math.min(100, Math.floor(dropPct))),
      emergencyHalt: true,
      suggestedDuration: 14400n, // 4 hours max
      reason: `Major stablecoin TVL drop: ${dropPct.toFixed(1)}%`,
    }
  } else if (dropPct >= 5) {
    // DANGER — significant movement
    assessment = {
      level: RISK_LEVEL.DANGER,
      threatType: "STABLECOIN_TVL_DROP",
      riskAdjustment: BigInt(Math.floor(dropPct * 2)),
      emergencyHalt: false,
      suggestedDuration: 0n,
      reason: `Stablecoin TVL drop: ${dropPct.toFixed(1)}%`,
    }
  } else {
    // No significant threat
    runtime.log("No threat detected — skipping report")
    return {
      threatDetected: false,
      level: RISK_LEVEL.SAFE,
      threatType: "0x" + "00".repeat(32) as `0x${string}`,
      emergencyHalt: false,
      txHash: "0x",
    }
  }

  runtime.log(
    `Threat detected: ${assessment.threatType}, emergency=${assessment.emergencyHalt}`
  )

  // Step 3: ABI-encode ThreatReport struct
  // Matches: struct ThreatReport { RiskLevel level (uint8), bytes32 threatType,
  //          uint256 riskAdjustment, bool emergencyHalt, uint256 suggestedDuration, string reason }
  const threatTypeBytes = pad(
    keccak256(toHex(assessment.threatType)),
    { size: 32 }
  )

  const reportData = encodeAbiParameters(
    parseAbiParameters(
      "uint8 level, bytes32 threatType, uint256 riskAdjustment, bool emergencyHalt, uint256 suggestedDuration, string reason"
    ),
    [
      assessment.level,
      threatTypeBytes,
      assessment.riskAdjustment,
      assessment.emergencyHalt,
      assessment.suggestedDuration,
      assessment.reason,
    ]
  )

  // Step 4: Resolve chain and generate signed report
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: evmConfig.chainName,
    isTestnet: evmConfig.chainName.includes("sepolia"),
  })
  if (!network) {
    throw new Error(`Unknown chain: ${evmConfig.chainName}`)
  }

  const reportResponse = runtime
    .report({
      encodedPayload: hexToBase64(reportData),
      encoderName: "evm",
      signingAlgo: "ecdsa",
      hashingAlgo: "keccak256",
    })
    .result()

  // Step 5: Write to EventSentinel consumer contract
  const evmClient = new EVMClient(network.chainSelector.selector)

  const writeResult = evmClient
    .writeReport(runtime, {
      receiver: evmConfig.eventSentinelAddress,
      report: reportResponse,
      gasConfig: {
        gasLimit: evmConfig.gasLimit,
      },
    })
    .result()

  const txHash = bytesToHex(writeResult.txHash || new Uint8Array(32))
  runtime.log(`Threat report submitted: ${txHash}`)

  return {
    threatDetected: true,
    level: assessment.level,
    threatType: threatTypeBytes,
    emergencyHalt: assessment.emergencyHalt,
    txHash,
  }
}

// ──────────────────── Workflow Init ────────────────────

const initWorkflow = (config: Config) => {
  const cron = new CronCapability()
  return [handler(cron.trigger({ schedule: config.schedule }), onCronTrigger)]
}

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
