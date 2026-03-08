/**
 * OSZILLOR Rebase Executor — CRE Workflow W3 (v2)
 *
 * Trigger: Cron every 5 minutes (300s)
 * Flow:    Cron → EVM Read (vault state + strategy positions + price feed)
 *          → Compute (target allocation + rebase factor) → EVM Write
 * Target:  RebaseExecutor.onReport(bytes metadata, bytes report)
 *
 * v2 changes:
 *   - Reads strategy.currentEthPct() for current portfolio allocation
 *   - Calculates targetEthPct based on risk tier (SAFE=100%, CAUTION=70%, DANGER=30%, CRITICAL=0%)
 *   - Encodes RebalanceReport (5 fields) instead of RebaseReport (4 fields)
 *   - On-chain: RebaseExecutor calls vault.rebalance(targetEthPct) THEN vault.triggerRebase(factor)
 *
 * All arithmetic uses bigint — NEVER floating point.
 */
import {
  CronCapability,
  EVMClient,
  handler,
  Runner,
  type Runtime,
  getNetwork,
  LAST_FINALIZED_BLOCK_NUMBER,
  encodeCallMsg,
  bytesToHex,
  hexToBase64,
} from "@chainlink/cre-sdk"
import {
  encodeFunctionData,
  decodeFunctionResult,
  encodeAbiParameters,
  parseAbiParameters,
  zeroAddress,
} from "viem"
import { OszillorVault, VaultStrategy } from "../contracts/abi"
import {
  calculateRebaseFactor,
  calculateTargetEthPct,
} from "./risk-math"

// ──────────────────── Config Types ────────────────────

type EvmConfig = {
  chainName: string
  vaultAddress: string
  strategyAddress: string
  rebaseExecutorAddress: string
  gasLimit: string
}

type Config = {
  schedule: string
  stakingApyBps: number // Lido staking APY in bps (e.g., 400 = 4%)
  evms: EvmConfig[]
}

type RebalanceResult = {
  rebaseFactor: bigint
  currentRiskScore: bigint
  targetEthPct: bigint
  weightedApyBps: bigint
  timeDelta: bigint
  txHash: string
}

// ──────────────────── EVM Read Helpers ────────────────────

function readVaultUint256(
  evmClient: EVMClient,
  runtime: Runtime<Config>,
  vaultAddr: `0x${string}`,
  functionName: "currentRiskScore" | "totalAssets"
): bigint {
  const callData = encodeFunctionData({
    abi: OszillorVault,
    functionName,
  })

  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddr,
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result()

  return decodeFunctionResult({
    abi: OszillorVault,
    functionName,
    data: bytesToHex(result.data),
  }) as bigint
}

function readVaultBool(
  evmClient: EVMClient,
  runtime: Runtime<Config>,
  vaultAddr: `0x${string}`,
  functionName: "emergencyMode"
): boolean {
  const callData = encodeFunctionData({
    abi: OszillorVault,
    functionName,
  })

  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddr,
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result()

  return decodeFunctionResult({
    abi: OszillorVault,
    functionName,
    data: bytesToHex(result.data),
  }) as boolean
}

function readStrategyUint256(
  evmClient: EVMClient,
  runtime: Runtime<Config>,
  strategyAddr: `0x${string}`,
  functionName: "currentEthPct" | "totalValueInEth"
): bigint {
  const callData = encodeFunctionData({
    abi: VaultStrategy,
    functionName,
  })

  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: strategyAddr,
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result()

  return decodeFunctionResult({
    abi: VaultStrategy,
    functionName,
    data: bytesToHex(result.data),
  }) as bigint
}

// ──────────────────── Main Logic ────────────────────

const onCronTrigger = (runtime: Runtime<Config>): RebalanceResult => {
  const evmConfig = runtime.config.evms[0]

  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: evmConfig.chainName,
    isTestnet: evmConfig.chainName.includes("sepolia"),
  })
  if (!network) {
    throw new Error(`Unknown chain: ${evmConfig.chainName}`)
  }

  const evmClient = new EVMClient(network.chainSelector.selector)
  const vaultAddr = evmConfig.vaultAddress as `0x${string}`
  const strategyAddr = evmConfig.strategyAddress as `0x${string}`

  // Step 1: Read current risk score from vault
  const currentRiskScore = readVaultUint256(evmClient, runtime, vaultAddr, "currentRiskScore")
  runtime.log(`Current risk score: ${currentRiskScore}`)

  // Step 2: Check emergency mode — skip rebase if active
  const isEmergency = readVaultBool(evmClient, runtime, vaultAddr, "emergencyMode")

  if (isEmergency) {
    runtime.log("Emergency mode active — skipping rebalance + rebase")
    return {
      rebaseFactor: 1_000_000_000_000_000_000n, // 1.0 (no change)
      currentRiskScore,
      targetEthPct: 0n, // Full hedge during emergency
      weightedApyBps: 0n,
      timeDelta: 300n,
      txHash: "0x",
    }
  }

  // Step 3: Read current strategy position
  const currentEthPct = readStrategyUint256(evmClient, runtime, strategyAddr, "currentEthPct")
  runtime.log(`Current ETH allocation: ${currentEthPct} bps`)

  // Step 4: Calculate target ETH allocation based on risk tier
  const targetEthPct = calculateTargetEthPct(currentRiskScore)
  runtime.log(`Target ETH allocation: ${targetEthPct} bps (risk: ${currentRiskScore})`)

  // Step 5: Calculate rebase factor based on staking yield
  const timeDelta = 300n // 5 minutes
  const stakingApyBps = BigInt(runtime.config.stakingApyBps || 400) // Default 4% Lido APY

  // In v2, weightedApyBps is simply the staking APY scaled by ETH exposure
  // If 70% ETH at 4% APY → effective yield = 70% * 4% = 2.8%
  const effectiveApyBps = (stakingApyBps * targetEthPct) / 10000n

  const rebaseFactor = calculateRebaseFactor(
    currentRiskScore,
    effectiveApyBps,
    timeDelta
  )

  runtime.log(
    `Rebase factor: ${rebaseFactor}, effective APY: ${effectiveApyBps}bps`
  )

  // Step 6: ABI-encode RebalanceReport struct
  // Matches: struct RebalanceReport {
  //   uint256 rebaseFactor, uint256 currentRiskScore,
  //   uint256 targetEthPct, uint256 weightedApyBps, uint256 timeDelta
  // }
  const reportData = encodeAbiParameters(
    parseAbiParameters(
      "uint256 rebaseFactor, uint256 currentRiskScore, uint256 targetEthPct, uint256 weightedApyBps, uint256 timeDelta"
    ),
    [rebaseFactor, currentRiskScore, targetEthPct, effectiveApyBps, timeDelta]
  )

  // Step 7: Generate signed report via DON consensus
  const reportResponse = runtime
    .report({
      encodedPayload: hexToBase64(reportData),
      encoderName: "evm",
      signingAlgo: "ecdsa",
      hashingAlgo: "keccak256",
    })
    .result()

  // Step 8: Write report to RebaseExecutor consumer contract
  const writeResult = evmClient
    .writeReport(runtime, {
      receiver: evmConfig.rebaseExecutorAddress,
      report: reportResponse,
      gasConfig: {
        gasLimit: evmConfig.gasLimit,
      },
    })
    .result()

  const txHash = bytesToHex(writeResult.txHash || new Uint8Array(32))
  runtime.log(`Rebalance + rebase report submitted: ${txHash}`)

  return {
    rebaseFactor,
    currentRiskScore,
    targetEthPct,
    weightedApyBps: effectiveApyBps,
    timeDelta,
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
