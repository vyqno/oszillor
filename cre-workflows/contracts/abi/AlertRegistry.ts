/**
 * AlertRegistry ABI — view functions used by CRE W4 workflow.
 * Only includes the functions the cron trigger needs to read.
 * `as const` is required for viem type inference.
 */
export const AlertRegistry = [
  {
    inputs: [{ internalType: "uint256", name: "ruleId", type: "uint256" }],
    name: "getRule",
    outputs: [
      {
        components: [
          { internalType: "address", name: "subscriber", type: "address" },
          { internalType: "enum AlertCondition", name: "condition", type: "uint8" },
          { internalType: "uint256", name: "threshold", type: "uint256" },
          { internalType: "string", name: "webhookUrl", type: "string" },
          { internalType: "uint256", name: "createdAt", type: "uint256" },
          { internalType: "uint256", name: "ttl", type: "uint256" },
          { internalType: "bool", name: "active", type: "bool" },
        ],
        internalType: "struct AlertRule",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getAllRuleIds",
    outputs: [{ internalType: "uint256[]", name: "", type: "uint256[]" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "uint256", name: "ruleId", type: "uint256" }],
    name: "isRuleActive",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "ruleCount",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const
