/**
 * OSZILLOR Rebase Executor — CRE Workflow W3
 *
 * Trigger: Cron every 5 minutes (300s)
 * Flow:    Cron → EVM Read (vault state) → Compute (factor calc) → EVM Write
 * Target:  RebaseExecutor.onReport(bytes metadata, bytes report)
 *
 * This workflow reads the current risk score and allocations from the vault,
 * calculates the appropriate rebase factor based on risk tier, and writes
 * a signed RebaseReport to the RebaseExecutor consumer contract.
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
import { OszillorVault } from "../contracts/abi"
import {
  calculateRebaseFactor,
  calculateWeightedApy,
  type Allocation,
} from "./risk-math"

// ──────────────────── Config Types ────────────────────

type EvmConfig = {
  chainName: string
  vaultAddress: string
  rebaseExecutorAddress: string
  gasLimit: string
}

type Config = {
  schedule: string
  evms: EvmConfig[]
}

type RebaseResult = {
  rebaseFactor: bigint
  currentRiskScore: bigint
  weightedApyBps: bigint
  timeDelta: bigint
  txHash: string
}

// ──────────────────── Workflow Init ────────────────────

const initWorkflow = (config: Config) => {
  const cron = new CronCapability()
  return [handler(cron.trigger({ schedule: config.schedule }), onCronTrigger)]
}

// ──────────────────── Main Logic ────────────────────

const onCronTrigger = (runtime: Runtime<Config>): RebaseResult => {
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

  // Step 1: Read current risk score from vault
  const riskScoreCallData = encodeFunctionData({
    abi: OszillorVault,
    functionName: "currentRiskScore",
  })

  const riskScoreResult = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddr,
        data: riskScoreCallData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result()

  const currentRiskScore = decodeFunctionResult({
    abi: OszillorVault,
    functionName: "currentRiskScore",
    data: bytesToHex(riskScoreResult.data),
  }) as bigint

  runtime.log(`Current risk score: ${currentRiskScore}`)

  // Step 2: Check emergency mode — skip rebase if active
  const emergencyCallData = encodeFunctionData({
    abi: OszillorVault,
    functionName: "emergencyMode",
  })

  const emergencyResult = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddr,
        data: emergencyCallData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result()

  const isEmergency = decodeFunctionResult({
    abi: OszillorVault,
    functionName: "emergencyMode",
    data: bytesToHex(emergencyResult.data),
  }) as boolean

  if (isEmergency) {
    runtime.log("Emergency mode active — skipping rebase")
    return {
      rebaseFactor: 1_000_000_000_000_000_000n,
      currentRiskScore,
      weightedApyBps: 0n,
      timeDelta: 300n,
      txHash: "0x",
    }
  }

  // Step 3: Read allocations from vault
  const allocCallData = encodeFunctionData({
    abi: OszillorVault,
    functionName: "getAllocations",
  })

  const allocResult = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: vaultAddr,
        data: allocCallData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result()

  const rawAllocations = decodeFunctionResult({
    abi: OszillorVault,
    functionName: "getAllocations",
    data: bytesToHex(allocResult.data),
  }) as readonly { protocol: string; percentageBps: bigint; apyBps: bigint }[]

  const allocations: Allocation[] = rawAllocations.map((a) => ({
    protocol: a.protocol,
    percentageBps: a.percentageBps,
    apyBps: a.apyBps,
  }))

  runtime.log(`Read ${allocations.length} allocations`)

  // Step 4: Calculate rebase factor
  const timeDelta = 300n // 5 minutes
  const weightedApyBps = calculateWeightedApy(allocations)
  const rebaseFactor = calculateRebaseFactor(
    currentRiskScore,
    weightedApyBps,
    timeDelta
  )

  runtime.log(
    `Calculated factor: ${rebaseFactor}, weightedApy: ${weightedApyBps}bps`
  )

  // Step 5: ABI-encode RebaseReport struct
  // Matches: struct RebaseReport { uint256 rebaseFactor, uint256 currentRiskScore, uint256 weightedApyBps, uint256 timeDelta }
  const reportData = encodeAbiParameters(
    parseAbiParameters(
      "uint256 rebaseFactor, uint256 currentRiskScore, uint256 weightedApyBps, uint256 timeDelta"
    ),
    [rebaseFactor, currentRiskScore, weightedApyBps, timeDelta]
  )

  // Step 6: Generate signed report via DON consensus
  const reportResponse = runtime
    .report({
      encodedPayload: hexToBase64(reportData),
      encoderName: "evm",
      signingAlgo: "ecdsa",
      hashingAlgo: "keccak256",
    })
    .result()

  // Step 7: Write report to RebaseExecutor consumer contract
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
  runtime.log(`Rebase report submitted: ${txHash}`)

  return {
    rebaseFactor,
    currentRiskScore,
    weightedApyBps,
    timeDelta,
    txHash,
  }
}

// ──────────────────── Entry Point ────────────────────

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
