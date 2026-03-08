/**
 * OSZILLOR Risk Intelligence API — Configuration
 *
 * Loads environment variables with sensible defaults for local development.
 */

export const config = {
  port: Number(process.env.PORT ?? 4021),

  /** Wallet address to receive x402 USDC payments (Base Sepolia) */
  payToAddress: process.env.PAY_TO_ADDRESS ?? "0x0000000000000000000000000000000000000000",

  /** x402 facilitator URL (Base Sepolia testnet) */
  facilitatorUrl: "https://x402.org/facilitator",

  /** x402 network identifier for Base Sepolia */
  network: "eip155:84532" as const,

  /** Ethereum Sepolia RPC for reading vault state */
  ethSepoliaRpc: process.env.ETH_SEPOLIA_RPC_URL ?? "https://rpc.sepolia.org",

  /** OszillorVault address on Ethereum Sepolia */
  vaultAddress: (process.env.VAULT_ADDRESS ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,

  /** VaultStrategy address on Ethereum Sepolia */
  strategyAddress: (process.env.STRATEGY_ADDRESS ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,

  /** Base Sepolia RPC for reading AlertRegistry */
  baseSepoliaRpc: process.env.BASE_SEPOLIA_RPC_URL ?? "https://sepolia.base.org",

  /** AlertRegistry address on Base Sepolia */
  alertRegistryAddress: (process.env.ALERT_REGISTRY_ADDRESS ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,

  /** CRE W4 HTTP trigger URL */
  creW4TriggerUrl: process.env.CRE_W4_HTTP_TRIGGER_URL ?? "",
} as const
