/**
 * OSZILLOR Risk Alerts — CRE Workflow W4 Types
 *
 * Shared types for HTTP + Cron dual-trigger workflow.
 */

/** Base Sepolia EVM config for AlertRegistry writes */
export type AlertEvmConfig = {
  chainName: string
  alertRegistryAddress: string
  gasLimit: string
}

/** Ethereum Sepolia EVM config for OszillorVault reads */
export type VaultEvmConfig = {
  chainName: string
  vaultAddress: string
}

/** W4 workflow configuration (from config.staging.json) */
export type Config = {
  /** Cron schedule for alert evaluation (e.g., "*/60 * * * * *") */
  schedule: string
  /** Base Sepolia — AlertRegistry deployment */
  alertEvm: AlertEvmConfig
  /** Ethereum Sepolia — OszillorVault (read-only) */
  vaultEvm: VaultEvmConfig
}

/** Alert condition types matching Solidity enum */
export const AlertCondition = {
  RISK_ABOVE: 0,
  RISK_BELOW: 1,
  EMERGENCY: 2,
} as const

/** HTTP trigger payload from Express API */
export type AlertRequest = {
  subscriber: `0x${string}`
  condition: number
  threshold: number
  webhookUrl: string
  ttl: number
}

/** On-chain alert rule read from AlertRegistry */
export type AlertRule = {
  subscriber: `0x${string}`
  condition: number
  threshold: bigint
  webhookUrl: string
  createdAt: bigint
  ttl: bigint
  active: boolean
}
