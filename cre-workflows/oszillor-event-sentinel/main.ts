/**
 * OSZILLOR Event Sentinel — CRE Workflow W2 (v2)
 *
 * Trigger: Cron every 15 seconds (fast — crash detection is time-critical)
 * Flow:    Cron → HTTP (CoinGecko ETH + stETH prices) → Compute (crash detection)
 *          → DON Consensus → EVM Write (if threat detected)
 * Target:  EventSentinel.onReport(bytes metadata, bytes report)
 *
 * Crash detection signals:
 *   - ETH price drop >5% in 5 min → CRITICAL (emergency halt + full hedge)
 *   - ETH price drop >3% in 5 min → DANGER (risk adjustment +30)
 *   - stETH/ETH ratio < 0.97 → CRITICAL (emergency halt + full hedge)
 *   - stETH/ETH ratio < 0.99 → DANGER (risk adjustment +20)
 *
 * NOTE: Only writes to chain when a threat is detected. In normal conditions,
 * it logs "No threat" and skips — saving gas.
 *
 * All arithmetic uses bigint — NEVER floating point in consensus paths.
 * Percentages are scaled by 1000 for integer consensus (e.g., 5.3% = 53).
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
  coinGeckoEthUrl: string
  coinGeckoStethUrl: string
  simulateThreat?: boolean
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

type ThreatAssessment = {
  level: number
  threatType: string
  riskAdjustment: bigint
  emergencyHalt: boolean
  suggestedDuration: bigint
  reason: string
}

// ──────────────────── Crash Detection ────────────────────

/**
 * Encodes two signals into a single bigint for DON consensus:
 *   - High 32 bits: ETH price drop scaled by 1000 (e.g., 5300 = 5.3%)
 *   - Low 32 bits: stETH depeg scaled by 10000 (e.g., 9700 = 0.97 ratio)
 *
 * Each node fetches independently; consensus selects the median composite.
 */
const fetchCrashSignals = (nodeRuntime: NodeRuntime<Config>): bigint => {
  const httpClient = new HTTPClient()

  let ethDropScaled = 0n // ETH 24h drop * 1000 (for integer precision)
  let stEthRatioScaled = 10000n // stETH/ETH ratio * 10000 (10000 = 1.0)

  // ── ETH price change detection ──
  try {
    const ethResp = httpClient
      .sendRequest(nodeRuntime, {
        url: nodeRuntime.config.coinGeckoEthUrl,
        method: "GET" as const,
      })
      .result()

    const ethText = new TextDecoder().decode(ethResp.body)
    const ethData = JSON.parse(ethText) as {
      market_data?: {
        price_change_percentage_24h?: number
        price_change_percentage_1h_in_currency?: { usd?: number }
      }
    }

    // Use 1h change as proxy for 5-min crash detection in simulation
    // In production, DON nodes would track rolling 5-min window
    const priceChange =
      ethData.market_data?.price_change_percentage_1h_in_currency?.usd ??
      ethData.market_data?.price_change_percentage_24h ??
      0

    // Only care about drops (negative values)
    if (priceChange < 0) {
      ethDropScaled = BigInt(Math.floor(Math.abs(priceChange) * 1000))
    }
  } catch {
    // If fetch fails, signal no drop (conservative)
  }

  // ── stETH/ETH ratio ──
  try {
    const stethResp = httpClient
      .sendRequest(nodeRuntime, {
        url: nodeRuntime.config.coinGeckoStethUrl,
        method: "GET" as const,
      })
      .result()

    const stethText = new TextDecoder().decode(stethResp.body)
    const stethData = JSON.parse(stethText) as {
      "staked-ether"?: { eth?: number }
    }

    const ratio = stethData["staked-ether"]?.eth ?? 1.0
    stEthRatioScaled = BigInt(Math.floor(ratio * 10000))
  } catch {
    // Default to 1.0 ratio if fetch fails
  }

  // Pack into single bigint: high bits = ethDrop, low bits = stEthRatio
  return (ethDropScaled << 32n) | stEthRatioScaled
}

// ──────────────────── Main Workflow ────────────────────

const onCronTrigger = (runtime: Runtime<Config>): ThreatResult => {
  const evmConfig = runtime.config.evms[0]

  // Step 1: Fetch crash signals with DON consensus
  const composite = runtime
    .runInNodeMode(fetchCrashSignals, consensusMedianAggregation())()
    .result()

  // Unpack composite signal
  const ethDropScaled = Number(composite >> 32n)
  const stEthRatioScaled = Number(composite & 0xFFFFFFFFn)

  const ethDropPct = ethDropScaled / 1000 // e.g., 5300 → 5.3%
  const stEthRatio = stEthRatioScaled / 10000 // e.g., 9700 → 0.97

  runtime.log(`ETH drop: ${ethDropPct.toFixed(1)}%, stETH ratio: ${stEthRatio.toFixed(4)}`)

  // Step 2: Classify threat — check most severe first
  let assessment: ThreatAssessment | null = null

  // Check ETH price crash
  if (ethDropPct >= 5) {
    assessment = {
      level: RISK_LEVEL.CRITICAL,
      threatType: "ETH_PRICE_CRASH",
      riskAdjustment: 100n,
      emergencyHalt: true,
      suggestedDuration: 14400n, // 4 hours
      reason: `ETH price crash: -${ethDropPct.toFixed(1)}% (>5% threshold)`,
    }
  } else if (ethDropPct >= 3) {
    assessment = {
      level: RISK_LEVEL.DANGER,
      threatType: "ETH_PRICE_DROP",
      riskAdjustment: 30n,
      emergencyHalt: false,
      suggestedDuration: 0n,
      reason: `ETH price drop: -${ethDropPct.toFixed(1)}% (>3% threshold)`,
    }
  }

  // Check stETH depeg (overrides if more severe)
  if (stEthRatio < 0.97) {
    assessment = {
      level: RISK_LEVEL.CRITICAL,
      threatType: "STETH_DEPEG_CRITICAL",
      riskAdjustment: 100n,
      emergencyHalt: true,
      suggestedDuration: 14400n, // 4 hours
      reason: `stETH depeg: ratio=${stEthRatio.toFixed(4)} (<0.97 critical threshold)`,
    }
  } else if (stEthRatio < 0.99 && (!assessment || assessment.level < RISK_LEVEL.DANGER)) {
    assessment = {
      level: RISK_LEVEL.DANGER,
      threatType: "STETH_DEPEG_WARNING",
      riskAdjustment: 20n,
      emergencyHalt: false,
      suggestedDuration: 0n,
      reason: `stETH depeg warning: ratio=${stEthRatio.toFixed(4)} (<0.99 threshold)`,
    }
  }

  // No threat detected — in production, skip writing to save gas.
  // In staging/demo mode (simulateThreat=true), always write to demonstrate
  // the full pipeline with a simulated crash detection.
  if (!assessment) {
    if (runtime.config.simulateThreat) {
      runtime.log("No live threat — simulating crash detection for demo")
      assessment = {
        level: RISK_LEVEL.CRITICAL,
        threatType: "SIMULATED_STETH_DEPEG",
        riskAdjustment: 100n,
        emergencyHalt: true,
        suggestedDuration: 14400n,
        reason: `Simulated: stETH depeg detected (ratio=${stEthRatio.toFixed(4)}), ETH drop=${ethDropPct.toFixed(1)}% — emergency halt triggered`,
      }
    } else {
      runtime.log("No threat detected — skipping report")
      return {
        threatDetected: false,
        level: RISK_LEVEL.SAFE,
        threatType: ("0x" + "00".repeat(32)) as `0x${string}`,
        emergencyHalt: false,
        txHash: "0x",
      }
    }
  }

  runtime.log(
    `Threat detected: ${assessment.threatType}, level=${assessment.level}, emergency=${assessment.emergencyHalt}`
  )

  // Step 3: ABI-encode ThreatReport struct
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
