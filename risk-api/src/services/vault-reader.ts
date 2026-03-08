/**
 * OSZILLOR Risk Intelligence API — Vault Reader Service
 *
 * Reads on-chain state from OszillorVault and VaultStrategy on Ethereum Sepolia
 * using viem public client. All operations are read-only (no wallet needed).
 */
import { createPublicClient, http, type PublicClient } from "viem"
import { sepolia } from "viem/chains"
import { config } from "../config"

// ──────────────────── ABIs (view functions only) ────────────────────

const VAULT_ABI = [
  {
    inputs: [],
    name: "currentRiskScore",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "riskState",
    outputs: [
      {
        components: [
          { name: "riskScore", type: "uint256" },
          { name: "confidence", type: "uint256" },
          { name: "timestamp", type: "uint256" },
          { name: "reasoningHash", type: "bytes32" },
        ],
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getAllocations",
    outputs: [
      {
        components: [
          { name: "protocol", type: "string" },
          { name: "percentageBps", type: "uint256" },
          { name: "apyBps", type: "uint256" },
        ],
        type: "tuple[]",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "emergencyMode",
    outputs: [{ type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalAssets",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const

const STRATEGY_ABI = [
  {
    inputs: [],
    name: "totalValueInEth",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "ethBalance",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "stableBalance",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "currentEthPct",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const

// ──────────────────── Client ────────────────────

let _client: PublicClient | null = null

function getClient(): PublicClient {
  if (!_client) {
    _client = createPublicClient({
      chain: sepolia,
      transport: http(config.ethSepoliaRpc),
    })
  }
  return _client
}

// ──────────────────── Read Functions ────────────────────

export type RiskState = {
  riskScore: bigint
  confidence: bigint
  timestamp: bigint
  reasoningHash: `0x${string}`
}

export async function readRiskState(): Promise<RiskState> {
  const client = getClient()
  const result = await client.readContract({
    address: config.vaultAddress,
    abi: VAULT_ABI,
    functionName: "riskState",
  })
  return result as unknown as RiskState
}

export async function readCurrentRiskScore(): Promise<bigint> {
  const client = getClient()
  return await client.readContract({
    address: config.vaultAddress,
    abi: VAULT_ABI,
    functionName: "currentRiskScore",
  }) as bigint
}

export async function readEmergencyMode(): Promise<boolean> {
  const client = getClient()
  return await client.readContract({
    address: config.vaultAddress,
    abi: VAULT_ABI,
    functionName: "emergencyMode",
  }) as boolean
}

export async function readTotalAssets(): Promise<bigint> {
  const client = getClient()
  return await client.readContract({
    address: config.vaultAddress,
    abi: VAULT_ABI,
    functionName: "totalAssets",
  }) as bigint
}

export type Allocation = {
  protocol: string
  percentageBps: bigint
  apyBps: bigint
}

export async function readAllocations(): Promise<Allocation[]> {
  const client = getClient()
  const result = await client.readContract({
    address: config.vaultAddress,
    abi: VAULT_ABI,
    functionName: "getAllocations",
  })
  return result as unknown as Allocation[]
}

export type StrategyState = {
  totalValueInEth: bigint
  ethBalance: bigint
  stableBalance: bigint
  currentEthPct: bigint
}

export async function readStrategyState(): Promise<StrategyState> {
  const client = getClient()
  const [totalValueInEth, ethBalance, stableBalance, currentEthPct] = await Promise.all([
    client.readContract({
      address: config.strategyAddress,
      abi: STRATEGY_ABI,
      functionName: "totalValueInEth",
    }),
    client.readContract({
      address: config.strategyAddress,
      abi: STRATEGY_ABI,
      functionName: "ethBalance",
    }),
    client.readContract({
      address: config.strategyAddress,
      abi: STRATEGY_ABI,
      functionName: "stableBalance",
    }),
    client.readContract({
      address: config.strategyAddress,
      abi: STRATEGY_ABI,
      functionName: "currentEthPct",
    }),
  ])

  return {
    totalValueInEth: totalValueInEth as bigint,
    ethBalance: ethBalance as bigint,
    stableBalance: stableBalance as bigint,
    currentEthPct: currentEthPct as bigint,
  }
}
