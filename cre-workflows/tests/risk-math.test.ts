/**
 * Unit tests for risk-math.ts — pure rebase factor calculation.
 *
 * These tests verify that our TypeScript factor calculation matches
 * the Solidity RiskMath.calculateRebaseFactor() exactly.
 *
 * Run: cd cre-workflows/tests && bun test risk-math.test.ts
 */
import { describe, expect, test } from "bun:test"
import {
  calculateRebaseFactor,
  calculateWeightedApy,
  clampFactor,
  riskLevel,
  PRECISION,
  MIN_REBASE_FACTOR,
  MAX_REBASE_FACTOR,
  CRITICAL_REBASE_FACTOR,
  SECONDS_PER_YEAR,
  type Allocation,
} from "../oszillor-rebase-executor/risk-math"

// ──────────────────── Risk Level Classification ────────────────────

describe("riskLevel", () => {
  test("0-39 is SAFE", () => {
    expect(riskLevel(0n)).toBe("SAFE")
    expect(riskLevel(20n)).toBe("SAFE")
    expect(riskLevel(39n)).toBe("SAFE")
  })

  test("40-69 is CAUTION", () => {
    expect(riskLevel(40n)).toBe("CAUTION")
    expect(riskLevel(50n)).toBe("CAUTION")
    expect(riskLevel(69n)).toBe("CAUTION")
  })

  test("70-89 is DANGER", () => {
    expect(riskLevel(70n)).toBe("DANGER")
    expect(riskLevel(80n)).toBe("DANGER")
    expect(riskLevel(89n)).toBe("DANGER")
  })

  test("90-100 is CRITICAL", () => {
    expect(riskLevel(90n)).toBe("CRITICAL")
    expect(riskLevel(95n)).toBe("CRITICAL")
    expect(riskLevel(100n)).toBe("CRITICAL")
  })
})

// ──────────────────── Factor Clamping ────────────────────

describe("clampFactor", () => {
  test("within bounds stays unchanged", () => {
    expect(clampFactor(PRECISION)).toBe(PRECISION)
    expect(clampFactor(1_005_000_000_000_000_000n)).toBe(
      1_005_000_000_000_000_000n
    )
  })

  test("below MIN clamps to MIN", () => {
    expect(clampFactor(980_000_000_000_000_000n)).toBe(MIN_REBASE_FACTOR)
    expect(clampFactor(0n)).toBe(MIN_REBASE_FACTOR)
  })

  test("above MAX clamps to MAX", () => {
    expect(clampFactor(1_020_000_000_000_000_000n)).toBe(MAX_REBASE_FACTOR)
    expect(clampFactor(2_000_000_000_000_000_000n)).toBe(MAX_REBASE_FACTOR)
  })

  test("boundary values", () => {
    expect(clampFactor(MIN_REBASE_FACTOR)).toBe(MIN_REBASE_FACTOR)
    expect(clampFactor(MAX_REBASE_FACTOR)).toBe(MAX_REBASE_FACTOR)
  })
})

// ──────────────────── Weighted APY ────────────────────

describe("calculateWeightedApy", () => {
  test("empty allocations returns 0", () => {
    expect(calculateWeightedApy([])).toBe(0n)
  })

  test("single 100% allocation returns its APY", () => {
    const allocs: Allocation[] = [
      { protocol: "aave-v3", percentageBps: 10_000n, apyBps: 500n },
    ]
    // 10000 * 500 / 10000 = 500
    expect(calculateWeightedApy(allocs)).toBe(500n)
  })

  test("weighted average of two allocations", () => {
    const allocs: Allocation[] = [
      { protocol: "aave-v3", percentageBps: 6_000n, apyBps: 400n }, // 60% at 4%
      { protocol: "compound", percentageBps: 4_000n, apyBps: 600n }, // 40% at 6%
    ]
    // (6000*400 + 4000*600) / 10000 = (2400000 + 2400000) / 10000 = 480
    expect(calculateWeightedApy(allocs)).toBe(480n)
  })
})

// ──────────────────── Rebase Factor Calculation ────────────────────

describe("calculateRebaseFactor", () => {
  test("CRITICAL tier returns fixed negative factor", () => {
    expect(calculateRebaseFactor(90n, 500n, 300n)).toBe(CRITICAL_REBASE_FACTOR)
    expect(calculateRebaseFactor(95n, 1000n, 600n)).toBe(CRITICAL_REBASE_FACTOR)
    expect(calculateRebaseFactor(100n, 0n, 0n)).toBe(CRITICAL_REBASE_FACTOR)
  })

  test("DANGER tier returns exactly 1e18 (no yield)", () => {
    expect(calculateRebaseFactor(70n, 500n, 300n)).toBe(PRECISION)
    expect(calculateRebaseFactor(80n, 1000n, 600n)).toBe(PRECISION)
    expect(calculateRebaseFactor(89n, 2000n, 3600n)).toBe(PRECISION)
  })

  test("SAFE tier: positive yield, factor > 1e18", () => {
    const factor = calculateRebaseFactor(20n, 500n, 300n)
    expect(factor).toBeGreaterThan(PRECISION)
    expect(factor).toBeLessThanOrEqual(MAX_REBASE_FACTOR)
  })

  test("CAUTION tier: 50% of SAFE yield", () => {
    const safeFactor = calculateRebaseFactor(20n, 500n, 300n)
    const cautionFactor = calculateRebaseFactor(50n, 500n, 300n)

    // Both should be above 1e18
    expect(safeFactor).toBeGreaterThan(PRECISION)
    expect(cautionFactor).toBeGreaterThan(PRECISION)

    // CAUTION yield should be roughly half of SAFE yield
    const safeYield = safeFactor - PRECISION
    const cautionYield = cautionFactor - PRECISION

    // Allow 1 wei difference due to integer division
    expect(cautionYield).toBe(safeYield / 2n)
  })

  test("zero APY produces factor = 1e18 for SAFE/CAUTION", () => {
    expect(calculateRebaseFactor(20n, 0n, 300n)).toBe(PRECISION)
    expect(calculateRebaseFactor(50n, 0n, 300n)).toBe(PRECISION)
  })

  test("zero time delta produces factor = 1e18 for SAFE/CAUTION", () => {
    expect(calculateRebaseFactor(20n, 500n, 0n)).toBe(PRECISION)
    expect(calculateRebaseFactor(50n, 500n, 0n)).toBe(PRECISION)
  })

  test("matches Solidity: 500bps APY, 300s, SAFE", () => {
    // Solidity: mulDiv(500 * 300, 1e18, 31557600 * 10000)
    // = mulDiv(150000, 1e18, 315576000000)
    // = 150000 * 1e18 / 315576000000
    // = 475_308_641_975n (approximately)
    const factor = calculateRebaseFactor(20n, 500n, 300n)
    const yield_ = factor - PRECISION

    // Expected: (500 * 300 * 1e18) / (31557600 * 10000)
    const expected = (500n * 300n * PRECISION) / (SECONDS_PER_YEAR * 10_000n)
    expect(yield_).toBe(expected)
  })

  test("extreme APY gets clamped to MAX", () => {
    // 100000 bps = 1000% APY, 1 year = should hit MAX_REBASE_FACTOR
    const factor = calculateRebaseFactor(20n, 100_000n, SECONDS_PER_YEAR)
    expect(factor).toBe(MAX_REBASE_FACTOR)
  })

  test("all bigint — no floating point precision loss", () => {
    // This specific case would lose precision with Number
    const factor = calculateRebaseFactor(20n, 777n, 301n)
    // Verify it's exactly reproducible
    const factor2 = calculateRebaseFactor(20n, 777n, 301n)
    expect(factor).toBe(factor2)
    // Verify it's a valid bigint
    expect(typeof factor).toBe("bigint")
  })
})

// ──────────────────── Boundary Tests ────────────────────

describe("tier boundaries", () => {
  test("score 39 is SAFE, score 40 is CAUTION", () => {
    const safe = calculateRebaseFactor(39n, 500n, 300n)
    const caution = calculateRebaseFactor(40n, 500n, 300n)

    // SAFE gets full yield, CAUTION gets half
    const safeYield = safe - PRECISION
    const cautionYield = caution - PRECISION
    expect(safeYield).toBeGreaterThan(cautionYield)
  })

  test("score 69 is CAUTION, score 70 is DANGER", () => {
    const caution = calculateRebaseFactor(69n, 500n, 300n)
    const danger = calculateRebaseFactor(70n, 500n, 300n)

    expect(caution).toBeGreaterThan(PRECISION)
    expect(danger).toBe(PRECISION) // Zero yield
  })

  test("score 89 is DANGER, score 90 is CRITICAL", () => {
    const danger = calculateRebaseFactor(89n, 500n, 300n)
    const critical = calculateRebaseFactor(90n, 500n, 300n)

    expect(danger).toBe(PRECISION) // Zero yield
    expect(critical).toBe(CRITICAL_REBASE_FACTOR) // Negative
    expect(critical).toBeLessThan(PRECISION)
  })
})
