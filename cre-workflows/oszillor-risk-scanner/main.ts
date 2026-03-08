/**
 * OSZILLOR Risk Scanner - CRE Workflow W1 (v2)
 *
 * Trigger: Cron every 30 seconds
 * Flow: Cron -> HTTP (risk + yield data) -> Compute -> DON consensus -> EVM write
 * Target: RiskEngine.onReport(bytes metadata, bytes report)
 */
import {
  CronCapability,
  HTTPClient,
  ConfidentialHTTPClient,
  EVMClient,
  handler,
  consensusMedianAggregation,
  consensusCommonPrefixAggregation,
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

type EvmConfig = {
  chainName: string
  riskEngineAddress: string
  ethUsdFeedAddress: string
  gasLimit: string
}

type Config = {
  schedule: string
  coinGeckoUrl: string
  defiLlamaUrl: string
  defiLlamaYieldsUrl: string
  premiumNewsUrl: string
  cryptoPanicUrl?: string
  llmApiUrl?: string
  llmModel?: string
  llmApiKey?: string
  llmTimeoutSeconds?: number
  yieldRotationThresholdBps?: number
  newsSecretKey?: string
  newsSecretNamespace?: string
  newsSecretOwner?: string
  evms: EvmConfig[]
}

type RiskResult = {
  riskScore: bigint
  confidence: bigint
  reasoningHash: `0x${string}`
  txHash: string
}

type DefiLlamaPool = {
  chain?: string
  project?: string
  symbol?: string
  apy?: number
  apyBase?: number
  apyReward?: number
}

type YieldOpportunity = {
  chain: string
  protocol: string
  apyBps: number
  status: "active" | "ccip-ready"
}

type ProtocolTarget = {
  label: string
  projectKeywords: string[]
  symbolKeywords?: string[]
}

type ChainTarget = {
  chainKey: string
  chainLabel: string
  status: "active" | "ccip-ready"
  protocols: ProtocolTarget[]
}

const STETH_PRICE_URL =
  "https://api.coingecko.com/api/v3/simple/price?ids=staked-ether,ethereum&vs_currencies=eth,usd"

const YIELD_TARGETS: ChainTarget[] = [
  {
    chainKey: "ethereum",
    chainLabel: "Ethereum",
    status: "active",
    protocols: [
      {
        label: "Lido stETH",
        projectKeywords: ["lido"],
        symbolKeywords: ["steth"],
      },
      {
        label: "Rocket Pool rETH",
        projectKeywords: ["rocket"],
        symbolKeywords: ["reth"],
      },
      {
        label: "Aave ETH",
        projectKeywords: ["aave"],
        symbolKeywords: ["eth"],
      },
    ],
  },
  {
    chainKey: "arbitrum",
    chainLabel: "Arbitrum",
    status: "ccip-ready",
    protocols: [
      {
        label: "GMX GLP",
        projectKeywords: ["gmx"],
        symbolKeywords: ["glp"],
      },
      {
        label: "Aave ETH",
        projectKeywords: ["aave"],
        symbolKeywords: ["eth"],
      },
      {
        label: "Radiant",
        projectKeywords: ["radiant"],
      },
    ],
  },
  {
    chainKey: "base",
    chainLabel: "Base",
    status: "ccip-ready",
    protocols: [
      {
        label: "Aerodrome",
        projectKeywords: ["aerodrome", "aero"],
      },
      {
        label: "Moonwell",
        projectKeywords: ["moonwell"],
      },
    ],
  },
  {
    chainKey: "optimism",
    chainLabel: "Optimism",
    status: "ccip-ready",
    protocols: [
      {
        label: "Velodrome",
        projectKeywords: ["velodrome"],
      },
      {
        label: "Aave ETH",
        projectKeywords: ["aave"],
        symbolKeywords: ["eth"],
      },
    ],
  },
  {
    chainKey: "polygon",
    chainLabel: "Polygon",
    status: "ccip-ready",
    protocols: [
      {
        label: "Aave ETH",
        projectKeywords: ["aave"],
        symbolKeywords: ["eth"],
      },
    ],
  },
]

const normalize = (value: string): string =>
  value.toLowerCase().replace(/[^a-z0-9]+/g, "")

const safeLabel = (value: string): string =>
  value.replace(/\|/g, "/").replace(/\s+/g, " ").trim()

const decodeJsonBody = <T>(body: Uint8Array): T => {
  const text = new TextDecoder().decode(body)
  return JSON.parse(text) as T
}

const encodeBodyBase64 = (value: string): string =>
  Buffer.from(value, "utf8").toString("base64")

const toApyBps = (pool: DefiLlamaPool): number | null => {
  const primary = pool.apy
  const blended =
    typeof pool.apyBase === "number" || typeof pool.apyReward === "number"
      ? (pool.apyBase ?? 0) + (pool.apyReward ?? 0)
      : undefined

  const apyPct =
    typeof primary === "number" && Number.isFinite(primary)
      ? primary
      : typeof blended === "number" && Number.isFinite(blended)
        ? blended
        : undefined

  if (typeof apyPct !== "number") {
    return null
  }

  return Math.max(0, Math.round(apyPct * 100))
}

const matchesProtocol = (pool: DefiLlamaPool, protocol: ProtocolTarget): boolean => {
  const project = normalize(pool.project ?? "")
  const symbol = normalize(pool.symbol ?? "")

  const projectMatch = protocol.projectKeywords.some((keyword) =>
    project.includes(normalize(keyword))
  )
  const symbolMatch = (protocol.symbolKeywords ?? []).some((keyword) =>
    symbol.includes(normalize(keyword))
  )

  return projectMatch || symbolMatch
}

const selectYieldOpportunities = (pools: DefiLlamaPool[]): YieldOpportunity[] => {
  const opportunities: YieldOpportunity[] = []

  for (const target of YIELD_TARGETS) {
    const chainPools = pools.filter((pool) =>
      normalize(pool.chain ?? "").includes(normalize(target.chainKey))
    )

    if (chainPools.length === 0) {
      continue
    }

    let selected:
      | {
          protocol: string
          apyBps: number
        }
      | undefined

    for (const protocol of target.protocols) {
      const match = chainPools
        .map((pool) => ({
          pool,
          apyBps: toApyBps(pool),
        }))
        .filter((item) => item.apyBps !== null && matchesProtocol(item.pool, protocol))
        .sort((a, b) => Number(b.apyBps) - Number(a.apyBps))[0]

      if (match && typeof match.apyBps === "number") {
        selected = {
          protocol: protocol.label,
          apyBps: match.apyBps,
        }
        break
      }
    }

    if (!selected) {
      const fallback = chainPools
        .map((pool) => ({
          pool,
          apyBps: toApyBps(pool),
        }))
        .filter((item) => item.apyBps !== null)
        .sort((a, b) => Number(b.apyBps) - Number(a.apyBps))[0]

      if (!fallback || typeof fallback.apyBps !== "number") {
        continue
      }

      selected = {
        protocol: safeLabel(
          `${fallback.pool.project ?? "Unknown"} ${fallback.pool.symbol ?? ""}`
        ),
        apyBps: fallback.apyBps,
      }
    }

    opportunities.push({
      chain: target.chainLabel,
      protocol: selected.protocol,
      apyBps: selected.apyBps,
      status: target.status,
    })
  }

  return opportunities
}

const encodeYieldLine = (opportunity: YieldOpportunity): string =>
  [
    safeLabel(opportunity.chain),
    safeLabel(opportunity.protocol),
    String(opportunity.apyBps),
    opportunity.status,
  ].join("|")

const decodeYieldLine = (line: string): YieldOpportunity | null => {
  const [chain, protocol, apyBpsRaw, statusRaw] = line.split("|")
  const apyBps = Number.parseInt(apyBpsRaw ?? "", 10)

  if (!chain || !protocol || !Number.isFinite(apyBps)) {
    return null
  }

  const status = statusRaw === "active" ? "active" : "ccip-ready"

  return {
    chain,
    protocol,
    apyBps,
    status,
  }
}

const toTier = (riskScore: bigint): "SAFE" | "CAUTION" | "DANGER" | "CRITICAL" => {
  if (riskScore >= 90n) return "CRITICAL"
  if (riskScore >= 70n) return "DANGER"
  if (riskScore >= 40n) return "CAUTION"
  return "SAFE"
}

const buildFallbackReasoning = (
  riskScore: bigint,
  opportunities: YieldOpportunity[]
): string => {
  const current = opportunities.find((item) => item.status === "active")
  const best = [...opportunities].sort((a, b) => b.apyBps - a.apyBps)[0]

  const currentText = current
    ? `${current.chain}/${current.protocol} at ${(current.apyBps / 100).toFixed(2)}%`
    : "no active source"
  const bestText = best
    ? `${best.chain}/${best.protocol} at ${(best.apyBps / 100).toFixed(2)}%`
    : "no cross-chain yield data"

  return `Risk tier ${toTier(riskScore)} (${riskScore}). Active source ${currentText}. Best observed opportunity ${bestText}. Recommendation: keep risk-adjusted positioning and rotate only when sustained differential exceeds threshold.`
}

const extractReasoningFromLlmPayload = (payload: unknown): string | null => {
  if (!payload || typeof payload !== "object") {
    return null
  }

  const raw = payload as {
    reasoning?: unknown
    analysis?: unknown
    output?: unknown
    choices?: Array<{
      message?: { content?: unknown }
      text?: unknown
    }>
  }

  if (typeof raw.reasoning === "string" && raw.reasoning.trim().length > 0) {
    return raw.reasoning.trim()
  }

  if (typeof raw.analysis === "string" && raw.analysis.trim().length > 0) {
    return raw.analysis.trim()
  }

  if (typeof raw.output === "string" && raw.output.trim().length > 0) {
    return raw.output.trim()
  }

  const firstChoice = raw.choices?.[0]
  if (typeof firstChoice?.message?.content === "string") {
    return firstChoice.message.content.trim()
  }

  if (typeof firstChoice?.text === "string") {
    return firstChoice.text.trim()
  }

  return null
}

const toReasoningTokens = (reasoning: string): string[] =>
  reasoning
    .replace(/\s+/g, " ")
    .trim()
    .split(" ")
    .filter((token) => token.length > 0)
    .slice(0, 120)

const buildNewsSecrets = (config: Config): Array<{
  key: string
  namespace: string
  owner?: string
}> => {
  const key = config.newsSecretKey?.trim() ?? ""
  const namespace = config.newsSecretNamespace?.trim() ?? ""

  if (!key || !namespace) {
    return []
  }

  const owner = config.newsSecretOwner?.trim()
  return [{ key, namespace, owner: owner || undefined }]
}

const fetchAndScoreRisk = (nodeRuntime: NodeRuntime<Config>): bigint => {
  const httpClient = new HTTPClient()

  let score = 15

  let geckoData:
    | {
        market_data?: {
          price_change_percentage_24h?: number
          price_change_percentage_7d?: number
        }
      }
    | undefined

  try {
    const geckoResp = httpClient
      .sendRequest(nodeRuntime, {
        url: nodeRuntime.config.coinGeckoUrl,
        method: "GET",
      })
      .result()

    geckoData = decodeJsonBody(geckoResp.body)
  } catch {
    score += 10
  }

  const priceChange24h = geckoData?.market_data?.price_change_percentage_24h ?? 0
  if (priceChange24h < -10) score += 30
  else if (priceChange24h < -5) score += 15
  else if (priceChange24h < -2) score += 5

  const change7d = Math.abs(geckoData?.market_data?.price_change_percentage_7d ?? 0)
  const change24h = Math.abs(geckoData?.market_data?.price_change_percentage_24h ?? 0)
  const estimatedAnnualVol = change7d * Math.sqrt(52)
  if (estimatedAnnualVol > 100) score += 20
  else if (estimatedAnnualVol > 60) score += 10
  else if (change24h > 5) score += 5

  try {
    const stethResp = httpClient
      .sendRequest(nodeRuntime, {
        url: STETH_PRICE_URL,
        method: "GET",
      })
      .result()

    const stethData = decodeJsonBody<{
      "staked-ether"?: { eth?: number }
    }>(stethResp.body)

    const stEthRatio = stethData["staked-ether"]?.eth ?? 1
    if (stEthRatio < 0.98) score += 25
    else if (stEthRatio < 0.995) score += 10
  } catch {
    // non-critical
  }

  try {
    const tvlResp = httpClient
      .sendRequest(nodeRuntime, {
        url: nodeRuntime.config.defiLlamaUrl,
        method: "GET",
      })
      .result()

    const chains = decodeJsonBody<Array<{ tvl: number; name: string }>>(tvlResp.body)

    const ethereum = chains.find((chain) => chain.name === "Ethereum")
    const totalTvl = chains.reduce((sum, chain) => sum + (chain.tvl || 0), 0)

    if (ethereum && totalTvl > 0) {
      const share = ethereum.tvl / totalTvl
      if (share < 0.3) score += 10
      else if (share < 0.4) score += 5
    }
  } catch {
    // non-critical
  }

  return BigInt(Math.min(100, Math.max(0, score)))
}

const fetchConfidentialNewsSignal = (runtime: Runtime<Config>): bigint => {
  const confidentialClient = new ConfidentialHTTPClient()

  try {
    const newsResp = confidentialClient
      .sendRequest(runtime, {
        vaultDonSecrets: buildNewsSecrets(runtime.config),
        request: {
          url: runtime.config.premiumNewsUrl,
          method: "GET",
        },
      })
      .result()

    const newsData = decodeJsonBody<{
      results?: Array<{ votes?: { negative?: number } }>
    }>(newsResp.body)

    const negativeCount = (newsData.results ?? []).filter(
      (item) => (item.votes?.negative ?? 0) > 2
    ).length

    if (negativeCount > 3) return 10n
    if (negativeCount > 1) return 5n
    return 0n
  } catch {
    return 0n
  }
}

const fetchCrossChainYieldLines = (nodeRuntime: NodeRuntime<Config>): string[] => {
  const httpClient = new HTTPClient()

  try {
    const yieldsResp = httpClient
      .sendRequest(nodeRuntime, {
        url: nodeRuntime.config.defiLlamaYieldsUrl,
        method: "GET",
      })
      .result()

    const decoded = decodeJsonBody<{ data?: DefiLlamaPool[] } | DefiLlamaPool[]>(
      yieldsResp.body
    )
    const pools = Array.isArray(decoded) ? decoded : decoded.data ?? []

    return selectYieldOpportunities(pools).map(encodeYieldLine)
  } catch {
    // DefiLlama /pools returns ~5-10MB which can overflow the WASM response buffer.
    // Yield data is non-critical — the risk score is the primary output.
    return []
  }
}

const fetchAiReasoningTokens = (
  nodeRuntime: NodeRuntime<Config>,
  riskScore: bigint,
  yieldLines: string[]
): string[] => {
  const opportunities = yieldLines
    .map(decodeYieldLine)
    .filter((item): item is YieldOpportunity => item !== null)

  const fallbackReasoning = buildFallbackReasoning(riskScore, opportunities)
  if (!nodeRuntime.config.llmApiUrl) {
    return toReasoningTokens(fallbackReasoning)
  }

  try {
    const httpClient = new HTTPClient()
    const prompt = [
      "You are OSZILLOR risk intelligence.",
      `Risk score: ${riskScore.toString()} (${toTier(riskScore)}).`,
      "Cross-chain yields:",
      ...opportunities.map(
        (item) =>
          `- ${item.chain}/${item.protocol}: ${(item.apyBps / 100).toFixed(2)}% (${item.status})`
      ),
      "Return compact JSON with keys: risk_assessment, yield_recommendation, allocation, reasoning.",
    ].join("\n")

    const response = httpClient
      .sendRequest(nodeRuntime, {
        url: nodeRuntime.config.llmApiUrl,
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(nodeRuntime.config.llmApiKey
            ? { authorization: `Bearer ${nodeRuntime.config.llmApiKey}` }
            : {}),
        },
        body: encodeBodyBase64(
          JSON.stringify({
            model: nodeRuntime.config.llmModel ?? "oszillor-risk-v1",
            prompt,
            riskScore: Number(riskScore),
            opportunities,
          })
        ),
      })
      .result()

    const parsed = decodeJsonBody<unknown>(response.body)
    const extracted = extractReasoningFromLlmPayload(parsed)

    if (!extracted || extracted.length === 0) {
      return toReasoningTokens(fallbackReasoning)
    }

    return toReasoningTokens(extracted)
  } catch {
    return toReasoningTokens(fallbackReasoning)
  }
}

const buildAllocationPayload = (
  opportunities: YieldOpportunity[],
  riskScore: bigint,
  rotationThresholdBps: number
): Array<{ protocol: string; percentageBps: bigint; apyBps: bigint }> => {
  if (opportunities.length === 0) {
    return []
  }

  const current = opportunities.find((item) => item.status === "active") ?? opportunities[0]

  const bestAlternative = opportunities
    .filter((item) => item.chain !== current.chain || item.protocol !== current.protocol)
    .sort((a, b) => b.apyBps - a.apyBps)[0]

  const shouldRotatePartially =
    !!bestAlternative &&
    riskScore <= 69n &&
    bestAlternative.apyBps - current.apyBps >= rotationThresholdBps

  if (shouldRotatePartially && bestAlternative) {
    return [
      {
        protocol: `${current.chain}/${current.protocol}`,
        percentageBps: 7000n,
        apyBps: BigInt(current.apyBps),
      },
      {
        protocol: `${bestAlternative.chain}/${bestAlternative.protocol}`,
        percentageBps: 3000n,
        apyBps: BigInt(bestAlternative.apyBps),
      },
    ]
  }

  return [
    {
      protocol: `${current.chain}/${current.protocol}`,
      percentageBps: 10_000n,
      apyBps: BigInt(current.apyBps),
    },
  ]
}

const onCronTrigger = (runtime: Runtime<Config>): RiskResult => {
  const evmConfig = runtime.config.evms[0]

  const nodeRiskScore = runtime
    .runInNodeMode(fetchAndScoreRisk, consensusMedianAggregation())()
    .result()
  const newsSignal = fetchConfidentialNewsSignal(runtime)
  const riskScore = nodeRiskScore + newsSignal > 100n ? 100n : nodeRiskScore + newsSignal

  // Yield + AI reasoning are enrichment — non-critical for the risk report.
  // DefiLlama /pools can overflow the WASM response buffer (~5-10MB response).
  let yieldLines: string[] = []
  try {
    yieldLines = runtime
      .runInNodeMode(fetchCrossChainYieldLines, consensusCommonPrefixAggregation<string>())()
      .result()
  } catch {
    runtime.log("Yield fetch failed (buffer overflow) — using fallback")
  }

  const opportunities = yieldLines
    .map(decodeYieldLine)
    .filter((item): item is YieldOpportunity => item !== null)

  let reasoningTokens: string[] = []
  try {
    reasoningTokens = runtime
      .runInNodeMode(fetchAiReasoningTokens, consensusCommonPrefixAggregation<string>())(
        riskScore,
        yieldLines
      )
      .result()
  } catch {
    runtime.log("AI reasoning failed — using fallback")
  }

  const reasoning =
    reasoningTokens.join(" ").trim() || buildFallbackReasoning(riskScore, opportunities)

  const reasoningHash = keccak256(toHex(reasoning))

  const confidenceBase = 75 + Math.min(10, opportunities.length * 2)
  const confidence = BigInt(confidenceBase)

  const rotationThresholdBps = runtime.config.yieldRotationThresholdBps ?? 100
  const allocations = buildAllocationPayload(
    opportunities,
    riskScore,
    rotationThresholdBps
  )

  runtime.log(`Risk score after consensus: ${nodeRiskScore}`)
  runtime.log(`News risk signal: +${newsSignal}`)
  runtime.log(`Cross-chain opportunities: ${yieldLines.length}`)
  runtime.log(`Reasoning hash: ${reasoningHash}`)

  const reportData = encodeAbiParameters(
    parseAbiParameters(
      "uint256 riskScore, uint256 confidence, bytes32 reasoningHash, (string protocol, uint256 percentageBps, uint256 apyBps)[] allocations"
    ),
    [riskScore, confidence, reasoningHash, allocations]
  )

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

const initWorkflow = (config: Config) => {
  const cron = new CronCapability()
  return [handler(cron.trigger({ schedule: config.schedule }), onCronTrigger)]
}

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
