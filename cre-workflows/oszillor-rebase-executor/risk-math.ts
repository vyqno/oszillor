/**
 * risk-math.ts — Pure rebase factor calculation logic.
 *
 * Mirrors contracts/src/libraries/RiskMath.sol exactly.
 * All arithmetic uses bigint — NEVER floating point.
 * This file is imported by the workflow AND by unit tests.
 */

// ──────────────────── Constants (match RiskMath.sol) ────────────────────

export const PRECISION = 1_000_000_000_000_000_000n // 1e18

export const SAFE_THRESHOLD = 40n
export const CAUTION_THRESHOLD = 40n
export const DANGER_THRESHOLD = 70n
export const CRITICAL_THRESHOLD = 90n

export const MIN_REBASE_FACTOR = 990_000_000_000_000_000n // 0.99e18
export const MAX_REBASE_FACTOR = 1_010_000_000_000_000_000n // 1.01e18
export const CRITICAL_REBASE_FACTOR = 995_000_000_000_000_000n // 0.995e18

export const SECONDS_PER_YEAR = 31_557_600n // 365.25 * 86400

// ──────────────────── Risk Level Classification ────────────────────

export type RiskLevel = "SAFE" | "CAUTION" | "DANGER" | "CRITICAL"

export function riskLevel(score: bigint): RiskLevel {
  if (score >= CRITICAL_THRESHOLD) return "CRITICAL"
  if (score >= DANGER_THRESHOLD) return "DANGER"
  if (score >= CAUTION_THRESHOLD) return "CAUTION"
  return "SAFE"
}

// ──────────────────── Factor Clamping ────────────────────

export function clampFactor(factor: bigint): bigint {
  if (factor < MIN_REBASE_FACTOR) return MIN_REBASE_FACTOR
  if (factor > MAX_REBASE_FACTOR) return MAX_REBASE_FACTOR
  return factor
}

// ──────────────────── Weighted APY Calculation ────────────────────

export type Allocation = {
  protocol: string
  percentageBps: bigint
  apyBps: bigint
}

/**
 * Calculates weighted average APY in basis points.
 * weightedApy = sum(alloc.percentageBps * alloc.apyBps) / 10000
 */
export function calculateWeightedApy(allocations: Allocation[]): bigint {
  if (allocations.length === 0) return 0n

  let weightedSum = 0n
  for (const alloc of allocations) {
    weightedSum += alloc.percentageBps * alloc.apyBps
  }
  return weightedSum / 10_000n
}

// ──────────────────── Rebase Factor Calculation ────────────────────

/**
 * Calculates the rebase factor — mirrors RiskMath.calculateRebaseFactor exactly.
 *
 * Uses Solidity-equivalent mulDiv: (a * b) / c with full precision.
 * In bigint, (a * b / c) is safe since JS bigint has arbitrary precision.
 *
 * @param score - Current risk score (0-100)
 * @param weightedApyBps - Weighted average APY in basis points
 * @param timeDelta - Seconds since last rebase
 * @returns Clamped rebase factor (1e18 precision)
 */
export function calculateRebaseFactor(
  score: bigint,
  weightedApyBps: bigint,
  timeDelta: bigint
): bigint {
  const level = riskLevel(score)

  if (level === "CRITICAL") {
    return CRITICAL_REBASE_FACTOR
  }

  if (level === "DANGER") {
    return PRECISION
  }

  // periodYield = (weightedApyBps * timeDelta * PRECISION) / (SECONDS_PER_YEAR * 10000)
  // This is the exact same formula as RiskMath.sol's Math.mulDiv
  let periodYield =
    (weightedApyBps * timeDelta * PRECISION) / (SECONDS_PER_YEAR * 10_000n)

  if (level === "CAUTION") {
    periodYield = periodYield / 2n // 50% yield
  }
  // SAFE: 100% yield (no adjustment)

  return clampFactor(PRECISION + periodYield)
}
