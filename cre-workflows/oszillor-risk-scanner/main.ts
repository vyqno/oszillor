/**
 * OSZILLOR Risk Scanner — CRE Workflow W1
 *
 * Trigger: Cron every 60 seconds
 * Flow:    Cron → HTTP (DefiLlama, confidential in prod) → Compute (risk scoring)
 *          → DON Consensus → EVM Write
 * Target:  RiskEngine.onReport(bytes metadata, bytes report)
 *
 * Fetches DeFi protocol TVL data, computes a risk score (0-100),
 * and writes a signed RiskReport to the RiskEngine consumer contract.
 *
 * Privacy: In production, DefiLlama calls use ConfidentialHTTPClient (TEE).
 * In staging/simulation, regular HTTPClient is used.
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
} from "viem"

// ──────────────────── Config Types ────────────────────

type EvmConfig = {
  chainName: string
  riskEngineAddress: string
  gasLimit: string
}

type Config = {
  schedule: string
  defiLlamaUrl: string
  evms: EvmConfig[]
}

type RiskResult = {
  riskScore: bigint
  confidence: bigint
  reasoningHash: `0x${string}`
  txHash: string
}

// ──────────────────── Risk Scoring Logic ────────────────────

/**
 * Fetches DeFi protocol data and computes a risk score.
 * Runs in node mode — each DON node executes independently,
 * then consensus selects the median score.
 */
const fetchAndScoreRisk = (nodeRuntime: NodeRuntime<Config>): bigint => {
  const httpClient = new HTTPClient()

  const resp = httpClient
    .sendRequest(nodeRuntime, {
      url: nodeRuntime.config.defiLlamaUrl,
      method: "GET" as const,
    })
    .result()

  const bodyText = new TextDecoder().decode(resp.body)

  // Parse DefiLlama chain TVL data and compute risk score
  // Uses /v2/chains (smaller response, WASM-compatible)
  try {
    const chains = JSON.parse(bodyText) as Array<{
      tvl: number
      tokenSymbol: string
      name: string
    }>

    // Take top 20 chains by TVL for analysis
    const topProtocols = chains
      .sort((a, b) => (b.tvl || 0) - (a.tvl || 0))
      .slice(0, 20)

    if (topProtocols.length === 0) {
      return 50n // Default CAUTION if no data
    }

    let riskFactors = 0

    // Factor 1: TVL concentration — if top chain has >60% of total, higher risk
    const totalTvl = topProtocols.reduce((sum, c) => sum + (c.tvl || 0), 0)
    const topChainShare = totalTvl > 0 ? (topProtocols[0].tvl || 0) / totalTvl : 0
    if (topChainShare > 0.7) riskFactors += 20 // Very concentrated
    else if (topChainShare > 0.5) riskFactors += 10

    // Factor 2: Number of active chains — fewer chains = higher risk
    const activeChains = topProtocols.filter((c) => (c.tvl || 0) > 1_000_000).length
    if (activeChains < 5) riskFactors += 15
    else if (activeChains < 10) riskFactors += 5

    // Factor 3: Base risk (market always has some risk)
    riskFactors += 15

    // Clamp to 0-100
    const score = Math.min(100, Math.max(0, riskFactors))
    return BigInt(score)
  } catch {
    // If parsing fails, return CAUTION score
    return 50n
  }
}

// ──────────────────── Main Workflow ────────────────────

const onCronTrigger = (runtime: Runtime<Config>): RiskResult => {
  const evmConfig = runtime.config.evms[0]

  // Step 1: Fetch risk data with DON consensus
  // Each node fetches DefiLlama independently, median score selected
  const riskScore = runtime
    .runInNodeMode(fetchAndScoreRisk, consensusMedianAggregation())()
    .result()

  runtime.log(`Risk score after consensus: ${riskScore}`)

  // Step 2: Compute confidence and reasoning hash
  const confidence = 85n // High confidence for aggregated data
  const reasoning = `DefiLlama TVL analysis: score=${riskScore}, timestamp=${runtime.now()}`
  const reasoningHash = keccak256(toHex(reasoning))

  runtime.log(`Reasoning hash: ${reasoningHash}`)

  // Step 3: ABI-encode RiskReport struct
  // Matches: struct RiskReport { uint256 riskScore, uint256 confidence, bytes32 reasoningHash, Allocation[] allocations }
  // Allocation = (string protocol, uint256 percentageBps, uint256 apyBps)
  const reportData = encodeAbiParameters(
    parseAbiParameters(
      "uint256 riskScore, uint256 confidence, bytes32 reasoningHash, (string protocol, uint256 percentageBps, uint256 apyBps)[] allocations"
    ),
    [
      riskScore,
      confidence,
      reasoningHash,
      [], // Empty allocations for now — risk-only update
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

  // Step 5: Write to RiskEngine consumer contract
  const evmClient = new EVMClient(network.chainSelector.selector)

  const writeResult = evmClient
    .writeReport(runtime, {
      receiver: evmConfig.riskEngineAddress,
      report: reportResponse,
      gasConfig: {
        gasLimit: evmConfig.gasLimit,
      },
    })
    .result()

  const txHash = bytesToHex(writeResult.txHash || new Uint8Array(32))
  runtime.log(`Risk report submitted: ${txHash}`)

  return {
    riskScore,
    confidence,
    reasoningHash,
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
