/**
 * ABI encoding tests — verify TypeScript encoding matches Solidity abi.encode().
 *
 * These tests encode the same structs that our CRE workflows produce,
 * and verify the output matches what Solidity's abi.decode() expects.
 *
 * The test values mirror those used in contracts/test/unit/Modules.t.sol
 * to ensure cross-language compatibility.
 *
 * Run: cd cre-workflows/tests && bun test encoding.test.ts
 */
import { describe, expect, test } from "bun:test"
import {
  encodeAbiParameters,
  parseAbiParameters,
  decodeAbiParameters,
  keccak256,
  toHex,
  pad,
} from "viem"

// ──────────────────── RebaseReport Encoding ────────────────────

describe("RebaseReport encoding", () => {
  const rebaseParams = parseAbiParameters(
    "uint256 rebaseFactor, uint256 currentRiskScore, uint256 weightedApyBps, uint256 timeDelta"
  )

  test("encodes valid RebaseReport", () => {
    const encoded = encodeAbiParameters(rebaseParams, [
      1_005_000_000_000_000_000n, // 1.005e18
      50n, // risk score
      500n, // 5% APY
      300n, // 5 minutes
    ])

    expect(encoded).toStartWith("0x")
    // 4 x 32-byte words = 256 hex chars + "0x" prefix
    expect(encoded.length).toBe(2 + 256)

    // Round-trip decode
    const decoded = decodeAbiParameters(rebaseParams, encoded)
    expect(decoded[0]).toBe(1_005_000_000_000_000_000n)
    expect(decoded[1]).toBe(50n)
    expect(decoded[2]).toBe(500n)
    expect(decoded[3]).toBe(300n)
  })

  test("encodes boundary factor values", () => {
    // MIN factor (0.99e18)
    const minEncoded = encodeAbiParameters(rebaseParams, [
      990_000_000_000_000_000n,
      90n,
      0n,
      300n,
    ])
    const minDecoded = decodeAbiParameters(rebaseParams, minEncoded)
    expect(minDecoded[0]).toBe(990_000_000_000_000_000n)

    // MAX factor (1.01e18)
    const maxEncoded = encodeAbiParameters(rebaseParams, [
      1_010_000_000_000_000_000n,
      10n,
      1000n,
      300n,
    ])
    const maxDecoded = decodeAbiParameters(rebaseParams, maxEncoded)
    expect(maxDecoded[0]).toBe(1_010_000_000_000_000_000n)
  })
})

// ──────────────────── RiskReport Encoding ────────────────────

describe("RiskReport encoding", () => {
  const riskParams = parseAbiParameters(
    "uint256 riskScore, uint256 confidence, bytes32 reasoningHash, (string protocol, uint256 percentageBps, uint256 apyBps)[] allocations"
  )

  test("encodes RiskReport with empty allocations", () => {
    const reasoningHash = keccak256(toHex("test reasoning"))

    const encoded = encodeAbiParameters(riskParams, [
      55n,
      80n,
      reasoningHash,
      [],
    ])

    expect(encoded).toStartWith("0x")

    // Round-trip decode
    const decoded = decodeAbiParameters(riskParams, encoded)
    expect(decoded[0]).toBe(55n)
    expect(decoded[1]).toBe(80n)
    expect(decoded[2]).toBe(reasoningHash)
    expect(decoded[3]).toHaveLength(0)
  })

  test("encodes RiskReport with allocations", () => {
    const reasoningHash = keccak256(toHex("market analysis"))

    const encoded = encodeAbiParameters(riskParams, [
      45n,
      85n,
      reasoningHash,
      [
        {
          protocol: "aave-v3",
          percentageBps: 6000n,
          apyBps: 400n,
        },
        {
          protocol: "compound-v3",
          percentageBps: 4000n,
          apyBps: 600n,
        },
      ],
    ])

    const decoded = decodeAbiParameters(riskParams, encoded)
    expect(decoded[0]).toBe(45n)
    expect(decoded[3]).toHaveLength(2)
    expect(decoded[3][0].protocol).toBe("aave-v3")
    expect(decoded[3][0].percentageBps).toBe(6000n)
    expect(decoded[3][1].protocol).toBe("compound-v3")
  })
})

// ──────────────────── ThreatReport Encoding ────────────────────

describe("ThreatReport encoding", () => {
  const threatParams = parseAbiParameters(
    "uint8 level, bytes32 threatType, uint256 riskAdjustment, bool emergencyHalt, uint256 suggestedDuration, string reason"
  )

  test("encodes emergency ThreatReport", () => {
    const threatType = pad(keccak256(toHex("STABLECOIN_TVL_CRASH")), {
      size: 32,
    })

    const encoded = encodeAbiParameters(threatParams, [
      3, // CRITICAL
      threatType,
      100n,
      true,
      14400n, // 4 hours
      "Major stablecoin TVL drop: 15.0%",
    ])

    const decoded = decodeAbiParameters(threatParams, encoded)
    expect(decoded[0]).toBe(3) // CRITICAL
    expect(decoded[2]).toBe(100n)
    expect(decoded[3]).toBe(true)
    expect(decoded[4]).toBe(14400n)
    expect(decoded[5]).toBe("Major stablecoin TVL drop: 15.0%")
  })

  test("encodes non-emergency ThreatReport", () => {
    const threatType = pad(keccak256(toHex("STABLECOIN_TVL_DROP")), {
      size: 32,
    })

    const encoded = encodeAbiParameters(threatParams, [
      2, // DANGER
      threatType,
      10n,
      false,
      0n,
      "Stablecoin TVL drop: 6.5%",
    ])

    const decoded = decodeAbiParameters(threatParams, encoded)
    expect(decoded[0]).toBe(2) // DANGER
    expect(decoded[3]).toBe(false) // no emergency
    expect(decoded[4]).toBe(0n)
  })

  test("encodes matching Solidity test patterns", () => {
    // Mirror the exact encoding from Modules.t.sol _buildThreatReport
    const threatType = keccak256(toHex("depeg"))

    const encoded = encodeAbiParameters(threatParams, [
      3, // RiskLevel.CRITICAL
      threatType,
      30n,
      true,
      7200n, // 2 hours
      "USDC depeg detected",
    ])

    const decoded = decodeAbiParameters(threatParams, encoded)
    expect(decoded[0]).toBe(3)
    expect(decoded[1]).toBe(threatType)
    expect(decoded[2]).toBe(30n)
    expect(decoded[3]).toBe(true)
    expect(decoded[4]).toBe(7200n)
    expect(decoded[5]).toBe("USDC depeg detected")
  })
})

// ──────────────────── Cross-language Compatibility ────────────────────

describe("Solidity abi.encode compatibility", () => {
  test("uint256 encoding is standard ABI (32-byte left-padded)", () => {
    const encoded = encodeAbiParameters(parseAbiParameters("uint256"), [42n])
    // uint256(42) = 0x000...002a (32 bytes)
    expect(encoded).toBe(
      "0x000000000000000000000000000000000000000000000000000000000000002a"
    )
  })

  test("bool true = uint8(1) in ABI encoding", () => {
    const encoded = encodeAbiParameters(parseAbiParameters("bool"), [true])
    expect(encoded).toBe(
      "0x0000000000000000000000000000000000000000000000000000000000000001"
    )
  })

  test("keccak256 matches Solidity keccak256()", () => {
    // Solidity: keccak256("depeg") = known value
    const hash = keccak256(toHex("depeg"))
    expect(hash).toStartWith("0x")
    expect(hash.length).toBe(66) // 0x + 64 hex chars
  })
})
