/**
 * Comprehensive contract error → human-readable message mapping.
 * Covers all 35 OszillorErrors + OpenZeppelin errors + wallet-level errors.
 */
const ERROR_MAP: Record<string, string> = {
  // ── Oszillor Vault / Core ──
  EmergencyModeActive: "Emergency mode is active. Deposits are temporarily blocked.",
  ZeroAmount: "Amount must be greater than zero.",
  ZeroAddress: "Invalid address provided.",
  DepositTooSmall: "Minimum deposit is 0.001 WETH.",
  WithdrawalExceedsBalance: "Withdrawal amount exceeds your available balance.",
  DurationTooLong: "Emergency duration exceeds maximum (4 hours).",
  InvalidAllocation: "Allocation percentages must sum to 100%.",
  FeeTooHigh: "Fee rate exceeds the maximum allowed.",
  InsufficientShares: "You don't have enough vault shares for this operation.",
  InsufficientShareAllowance: "Insufficient share allowance. Please approve first.",
  RebaseFactorOutOfBounds: "Rebase factor is outside the allowed range.",
  ScoreJumpTooLarge: "Risk score change is too large for a single update.",
  ConfidenceTooLow: "DON consensus confidence is below minimum threshold.",
  UpdateTooFrequent: "Please wait before submitting another update.",
  RiskStateTooStale: "Risk data is stale. Waiting for CRE workflow update.",
  IndexDivergenceTooHigh: "Token index has diverged too far — potential issue.",
  SystemPaused: "The system is currently paused for safety.",
  DonationDetected: "Unexpected balance change detected. Donation attack blocked.",
  InsufficientLiquidity: "Not enough liquidity available for this operation.",
  InvalidRiskScore: "Risk score must be between 0 and 100.",
  EmergencyTooFrequent: "Emergency mode was recently active. Please wait.",

  // ── Strategy ──
  SlippageTooHigh: "Price slippage exceeds the 1% safety limit.",
  InvalidTargetAllocation: "Target allocation must be between 0% and 100%.",
  StrategyPaused: "Strategy operations are currently paused.",
  StalePriceFeed: "Chainlink price feed is stale. Waiting for update.",

  // ── CCIP / Cross-chain ──
  InsufficientLinkForFees: "Not enough LINK tokens to cover CCIP fees.",
  InvalidToken: "Token is not supported for this operation.",
  InvalidTokenAmount: "Invalid token amount for bridging.",
  ZeroSharesBridged: "Cannot bridge zero shares.",
  InboundMessageNotSupported: "This message type is not supported.",

  // ── CRE / Workflow ──
  NotForwarder: "Caller is not the authorized Chainlink forwarder.",
  WrongWorkflow: "Report came from an unexpected CRE workflow.",
  WrongOwner: "Report owner does not match expected address.",
  WrongName: "Workflow name does not match expected value.",
  ReplayDetected: "This report has already been processed (replay attack blocked).",
  MessageTooOld: "Report timestamp is too old to accept.",
  UnknownMessageType: "Unrecognized message type in CRE report.",

  // ── OpenZeppelin Standard ──
  ERC20InsufficientBalance: "Insufficient token balance for this transfer.",
  ERC20InsufficientAllowance: "Token allowance too low. Please approve first.",
  OwnableUnauthorizedAccount: "You are not authorized for this operation.",
  AccessControlUnauthorizedAccount: "Your account does not have the required role.",
  EnforcedPause: "This operation is paused.",
  ExpectedPause: "Expected the contract to be paused.",
};

/** Parse a caught error into a human-readable message. */
export function parseContractError(e: unknown): string {
  const msg = (e as Error)?.message || String(e);

  // Check wallet-level errors first
  if (msg.includes("User rejected") || msg.includes("user rejected") || msg.includes("ACTION_REJECTED")) {
    return "Transaction rejected by user.";
  }
  if (msg.includes("insufficient funds") || msg.includes("gas required exceeds")) {
    return "Insufficient ETH for gas. Get Sepolia ETH from a faucet.";
  }
  if (msg.includes("nonce")) {
    return "Transaction nonce conflict. Please reset your wallet or wait.";
  }

  // Check for custom contract errors
  for (const [errorName, message] of Object.entries(ERROR_MAP)) {
    if (msg.includes(errorName)) return message;
  }

  // Fallback
  return "Transaction failed. Please try again.";
}
