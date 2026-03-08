import { getContract } from "thirdweb";
import { sepolia } from "thirdweb/chains";
import { client } from "../client";

// ── Addresses ──────────────────────────────────────────────
export const VAULT_ADDRESS = process.env.NEXT_PUBLIC_VAULT_ADDRESS as string;
export const WETH_ADDRESS = process.env.NEXT_PUBLIC_WETH_ADDRESS as string;
export const OSZ_ADDRESS = process.env.NEXT_PUBLIC_TOKEN_ADDRESS as string;
export const STRATEGY_ADDRESS = process.env.NEXT_PUBLIC_STRATEGY_ADDRESS as string;

// ── Contract Instances ─────────────────────────────────────
export const vaultContract = getContract({
  client,
  chain: sepolia,
  address: VAULT_ADDRESS,
});

export const wethContract = getContract({
  client,
  chain: sepolia,
  address: WETH_ADDRESS,
});

export const oszContract = getContract({
  client,
  chain: sepolia,
  address: OSZ_ADDRESS,
});

export const strategyContract = getContract({
  client,
  chain: sepolia,
  address: STRATEGY_ADDRESS,
});

// ── Vault ABI (named exports) ──────────────────────────────
export const VAULT_ABI = {
  deposit: "function deposit(uint256 assets, address receiver) external returns (uint256 shares)",
  withdraw: "function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares)",
  totalAssets: "function totalAssets() external view returns (uint256)",
  paused: "function paused() external view returns (bool)",
  emergencyMode: "function emergencyMode() external view returns (bool)",
  currentRiskScore: "function currentRiskScore() external view returns (uint256)",
  maxDeposit: "function maxDeposit(address) external view returns (uint256)",
  maxWithdraw: "function maxWithdraw(address owner) external view returns (uint256)",
  riskLevel: "function riskLevel() external view returns (uint8)",
  totalNav: "function totalNav() external view returns (uint256)",
} as const;

// ── Strategy ABI ───────────────────────────────────────────
export const STRATEGY_ABI = {
  totalValueInEth: "function totalValueInEth() external view returns (uint256)",
  ethBalance: "function ethBalance() external view returns (uint256)",
  stableBalance: "function stableBalance() external view returns (uint256)",
  currentEthPct: "function currentEthPct() public view returns (uint256)",
} as const;

// ── ERC20 ABI ──────────────────────────────────────────────
export const ERC20_ABI = {
  approve: "function approve(address spender, uint256 amount) external returns (bool)",
  allowance: "function allowance(address owner, address spender) external view returns (uint256)",
  balanceOf: "function balanceOf(address account) external view returns (uint256)",
  mint: "function mint(address to, uint256 amount) external",
  symbol: "function symbol() external view returns (string)",
  decimals: "function decimals() external view returns (uint8)",
} as const;
