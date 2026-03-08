import { getContract } from "thirdweb";
import { sepolia } from "thirdweb/chains";
import { client } from "../client";

export const VAULT_ADDRESS = process.env.NEXT_PUBLIC_VAULT_ADDRESS as string;
export const WETH_ADDRESS = process.env.NEXT_PUBLIC_WETH_ADDRESS as string;
export const OSZ_ADDRESS = process.env.NEXT_PUBLIC_TOKEN_ADDRESS as string;
export const STRATEGY_ADDRESS = process.env.NEXT_PUBLIC_STRATEGY_ADDRESS as string;

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

export const vaultAbi = [
  "function deposit(uint256 assets) external returns (uint256)",
  "function totalAssets() external view returns (uint256)",
  "function paused() external view returns (bool)",
  "function withdraw(uint256 assets) external returns (uint256)",
  "function currentRiskScore() external view returns (uint256)",
  "function emergencyMode() external view returns (bool)",
] as const;

export const erc20Abi = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function mint(address to, uint256 amount) external",
] as const;
