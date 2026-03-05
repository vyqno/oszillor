/**
 * OszillorVault ABI — view functions used by CRE workflows.
 * Only includes the functions workflows need to read.
 * `as const` is required for viem type inference.
 */
export const OszillorVault = [
  {
    inputs: [],
    name: "currentRiskScore",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "riskState",
    outputs: [
      {
        components: [
          { internalType: "uint256", name: "riskScore", type: "uint256" },
          { internalType: "uint256", name: "confidence", type: "uint256" },
          { internalType: "uint256", name: "timestamp", type: "uint256" },
          { internalType: "bytes32", name: "reasoningHash", type: "bytes32" },
        ],
        internalType: "struct RiskState",
        name: "",
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
          { internalType: "string", name: "protocol", type: "string" },
          { internalType: "uint256", name: "percentageBps", type: "uint256" },
          { internalType: "uint256", name: "apyBps", type: "uint256" },
        ],
        internalType: "struct Allocation[]",
        name: "",
        type: "tuple[]",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "emergencyMode",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalAssets",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const
