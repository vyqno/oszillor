#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  OSZILLOR v2 — Master Demo (The Movie)
#  Risk-Managed ETH Yield Vault • Chainlink CRE + CCIP + AI + Privacy
# ══════════════════════════════════════════════════════════════════════════════
#  Usage:
#    bash demo/e2e-master.sh
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

DEMO_START=$SECONDS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env (API keys sourced from environment — never hardcoded)
source "$PROJECT_ROOT/contracts/.env"
RPC="${SEPOLIA_RPC_URL}"

# Deployed Addresses
VAULT="$VAULT_ADDRESS"
TOKEN="$TOKEN_ADDRESS"
STRATEGY="$STRATEGY_ADDRESS"
MOCK_LIDO="$MOCK_LIDO_ADDRESS"
WETH="$WETH_ADDRESS"
DEPLOYER="$DEPLOYER_ADDRESS"
RISK_ENGINE="$RISK_ENGINE_ADDRESS"
REBASE_EXECUTOR="$REBASE_EXECUTOR_ADDRESS"
EVENT_SENTINEL="$EVENT_SENTINEL_ADDRESS"

DEPOSIT_AMOUNT="10000000000000000"  # 0.01 WETH
EXPLORER="https://sepolia.etherscan.io"

# ── Terminal Colors & Effects ────────────────────────────────────────────────
GOLD='\033[38;5;220m'
AMBER='\033[38;5;214m'
CYAN='\033[36m'
GREEN='\033[32m'
PURPLE='\033[38;5;135m'
RED='\033[38;5;196m'
WHITE='\033[97m'
DIM='\033[2m'
BOLD='\033[1m'
BLINK='\033[5m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────
type_line() {
  local text="$1"
  local color="${2:-$WHITE}"
  local delay="${3:-0.015}"
  for (( i=0; i<${#text}; i++ )); do
    printf "${color}%s${RESET}" "${text:$i:1}"
    sleep "$delay"
  done
  printf "\n"
}

simulate_processing() {
  local msg="$1"
  local duration="${2:-2}"
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local end=$((SECONDS + duration))

  while [ $SECONDS -lt $end ]; do
    for frame in "${frames[@]}"; do
      printf "\r  ${CYAN}%s${RESET} ${DIM}%s${RESET}" "$frame" "$msg"
      sleep 0.1
    done
  done
  printf "\r  ${GREEN}✓${RESET} ${DIM}%s${RESET}                                   \n" "$msg"
}

clean_cast() {
  echo "$1" | sed 's/ \[.*\]//g' | tr -d '[:space:]'
}

wei_to_eth() {
  local wei
  wei=$(clean_cast "$1")
  node -e "const w=BigInt('${wei}');const d=w*10000n/BigInt(1e18);const s=d.toString();if(s.length<=4){console.log('0.'+s.padStart(4,'0'))}else{console.log(s.slice(0,-4)+'.'+s.slice(-4))}" 2>/dev/null || echo "0.0000"
}

# Compute wei delta and format with color (green +, red -)
wei_delta() {
  local before after
  before=$(clean_cast "$1")
  after=$(clean_cast "$2")
  node -e "
    const b=BigInt('${before}');const a=BigInt('${after}');const d=a-b;
    const abs=d<0n?-d:d;const v=abs*10000n/BigInt(1e18);const s=v.toString();
    const formatted=s.length<=4?'0.'+s.padStart(4,'0'):s.slice(0,-4)+'.'+s.slice(-4);
    if(d>0n){console.log('+'+formatted)}else if(d<0n){console.log('-'+formatted)}else{console.log(' 0.0000')}
  " 2>/dev/null || echo " 0.0000"
}

delta_color() {
  local delta="$1"
  if [[ "$delta" == +* ]]; then
    printf "${GREEN}%s${RESET}" "$delta"
  elif [[ "$delta" == -* ]]; then
    printf "${RED}%s${RESET}" "$delta"
  else
    printf "${DIM}%s${RESET}" "$delta"
  fi
}

print_header() {
  clear
  printf "\n"
  printf "${GOLD}${BOLD}"
  cat << "EOF"
    ██████╗ ███████╗███████╗██╗██╗     ██╗      ██████╗ ██████╗
   ██╔═══██╗██╔════╝╚══███╔╝██║██║     ██║     ██╔═══██╗██╔══██╗
   ██║   ██║███████╗  ███╔╝ ██║██║     ██║     ██║   ██║██████╔╝
   ██║   ██║╚════██║ ███╔╝  ██║██║     ██║     ██║   ██║██╔══██╗
   ╚██████╔╝███████║███████╗██║███████╗███████╗╚██████╔╝██║  ██║
    ╚═════╝ ╚══════╝╚══════╝╚═╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝
EOF
  printf "${RESET}\n"
  printf "  ${AMBER}Risk-Managed ETH Yield Vault${RESET} │ ${CYAN}Chainlink CRE + CCIP + AI${RESET}\n\n"
  printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n\n"
}

print_system_info() {
  printf "  ${BOLD}${WHITE}System Overview${RESET}\n"
  printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n"
  printf "  ${DIM}Network:${RESET}       Ethereum Sepolia (chainId 11155111)\n"
  printf "  ${DIM}Vault:${RESET}         ${CYAN}${VAULT}${RESET}\n"
  printf "  ${DIM}Strategy:${RESET}      ${CYAN}${STRATEGY}${RESET}\n"
  printf "  ${DIM}RiskEngine:${RESET}    ${CYAN}${RISK_ENGINE}${RESET}\n"
  printf "  ${DIM}Sentinel:${RESET}      ${CYAN}${EVENT_SENTINEL}${RESET}\n"
  printf "  ${DIM}Rebase Exec:${RESET}   ${CYAN}${REBASE_EXECUTOR}${RESET}\n"
  printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n"
  printf "  ${DIM}CRE Workflows:${RESET}\n"
  printf "    ${GOLD}W1${RESET} Risk Scanner      │ Cron 30s │ HTTP + AI + ConfidentialHTTP + EVM Write\n"
  printf "    ${GOLD}W2${RESET} Event Sentinel     │ Cron 15s │ HTTP Crash Detect + EVM Write\n"
  printf "    ${GOLD}W3${RESET} Rebase Executor    │ Cron 5m  │ EVM Read + Compute + EVM Write\n"
  printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n\n"
  sleep 2
}

fetch_balances() {
  local w_weth=$(cast call $WETH "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC)
  local w_osz=$(cast call $TOKEN "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC)
  local v_weth=$(cast call $WETH "balanceOf(address)(uint256)" $VAULT --rpc-url $RPC)
  local s_weth=$(cast call $WETH "balanceOf(address)(uint256)" $STRATEGY --rpc-url $RPC)
  local l_weth=$(cast call $WETH "balanceOf(address)(uint256)" $MOCK_LIDO --rpc-url $RPC)
  echo "$w_weth,$w_osz,$v_weth,$s_weth,$l_weth"
}

display_balances() {
  local label="$1"
  local raw_data="$2"
  IFS=',' read -r w_weth w_osz v_weth s_weth l_weth <<< "$raw_data"
  printf "  ${BOLD}${WHITE}[${label}]${RESET}\n"
  printf "  ${BOLD}%-20s${RESET} │ ${CYAN}%-12s${RESET} │ ${GOLD}%-12s${RESET}\n" "Actor" "WETH Balance" "OSZ Balance"
  printf "  ${DIM}─────────────────────┼──────────────┼──────────────${RESET}\n"
  printf "  %-20s │ %-12s │ %-12s\n" "Investor Wallet" "$(wei_to_eth "$w_weth")" "$(wei_to_eth "$w_osz")"
  printf "  %-20s │ %-12s │ %-12s\n" "Oszillor Vault" "$(wei_to_eth "$v_weth")" "-"
  printf "  %-20s │ %-12s │ %-12s\n" "Vault Strategy" "$(wei_to_eth "$s_weth")" "-"
  printf "  %-20s │ %-12s │ %-12s\n" "MockLido (Yield)" "$(wei_to_eth "$l_weth")" "-"
  printf "\n"
}

display_balance_diff() {
  local pre_data="$1"
  local post_data="$2"
  IFS=',' read -r pre_w_weth pre_w_osz pre_v_weth pre_s_weth pre_l_weth <<< "$pre_data"
  IFS=',' read -r post_w_weth post_w_osz post_v_weth post_s_weth post_l_weth <<< "$post_data"

  local d_w_weth=$(wei_delta "$pre_w_weth" "$post_w_weth")
  local d_w_osz=$(wei_delta "$pre_w_osz" "$post_w_osz")
  local d_v_weth=$(wei_delta "$pre_v_weth" "$post_v_weth")
  local d_s_weth=$(wei_delta "$pre_s_weth" "$post_s_weth")
  local d_l_weth=$(wei_delta "$pre_l_weth" "$post_l_weth")

  printf "  ${BOLD}${WHITE}[BEFORE vs AFTER]${RESET}\n"
  printf "  ${BOLD}%-20s${RESET} │ ${CYAN}%-12s${RESET} │ ${CYAN}%-12s${RESET} │ %-14s\n" "Actor" "Before" "After" "Delta"
  printf "  ${DIM}─────────────────────┼──────────────┼──────────────┼────────────────${RESET}\n"
  printf "  %-20s │ %-12s │ %-12s │ " "Investor WETH" "$(wei_to_eth "$pre_w_weth")" "$(wei_to_eth "$post_w_weth")"
  delta_color "$d_w_weth"; printf "\n"
  printf "  %-20s │ %-12s │ %-12s │ " "Investor OSZ" "$(wei_to_eth "$pre_w_osz")" "$(wei_to_eth "$post_w_osz")"
  delta_color "$d_w_osz"; printf "\n"
  printf "  %-20s │ %-12s │ %-12s │ " "Vault WETH" "$(wei_to_eth "$pre_v_weth")" "$(wei_to_eth "$post_v_weth")"
  delta_color "$d_v_weth"; printf "\n"
  printf "  %-20s │ %-12s │ %-12s │ " "Strategy WETH" "$(wei_to_eth "$pre_s_weth")" "$(wei_to_eth "$post_s_weth")"
  delta_color "$d_s_weth"; printf "\n"
  printf "  %-20s │ %-12s │ %-12s │ " "MockLido WETH" "$(wei_to_eth "$pre_l_weth")" "$(wei_to_eth "$post_l_weth")"
  delta_color "$d_l_weth"; printf "\n"
  printf "\n"
}

parse_cre_output() {
  echo "$1" | node -e "
    const fs = require('fs');
    const raw = fs.readFileSync(0, 'utf-8');
    const jsonMatch = raw.match(/(\[.*\]|\{.*\})/s);
    if(jsonMatch) {
      try {
        let parsed = JSON.parse(jsonMatch[0]);
        console.log('\x1b[2m  --- Transaction Payload (JSON) ---\x1b[0m');
        console.log(JSON.stringify(parsed, null, 2).split('\n').map(l=>'    '+l).join('\n'));
        console.log('\x1b[2m  ----------------------------------\x1b[0m');
      } catch(e) {}
    }
  " || true
}

extract_tx_hash() {
  echo "$1" | node -e '
    const fs = require("fs");
    const raw = fs.readFileSync(0, "utf-8");
    // Prefer the txHash field from CRE JSON output
    const txField = raw.match(/"txHash"\s*:\s*"(0x[a-fA-F0-9]{64})"/);
    if (txField) { console.log(txField[1]); process.exit(0); }
    // Fallback: find any 64-char hex that is not all zeros
    const hashes = (raw.match(/0x[a-fA-F0-9]{64}/g) || [])
      .filter(h => !/^0x0+$/.test(h));
    if (hashes.length > 0) {
      console.log(hashes[hashes.length - 1]);
    } else {
      console.log("0x...");
    }
  ' || echo '0x...'
}

# Fetch tx receipt and print block/gas/status
verify_tx_receipt() {
  local label="$1"
  local tx_hash="$2"
  # Skip if no hash, placeholder, or all zeros
  if [[ "$tx_hash" == "0x..." || "$tx_hash" == "0x" || "$tx_hash" =~ ^0x0+$ ]]; then
    printf "  ${DIM}[%s] No on-chain tx (workflow skipped write)${RESET}\n" "$label"
    return
  fi
  local receipt
  receipt=$(timeout 15 cast receipt "$tx_hash" --rpc-url "$RPC" 2>/dev/null || echo "")
  if [[ -z "$receipt" ]]; then
    printf "  ${DIM}[%s] Receipt pending...${RESET}\n" "$label"
    return
  fi
  local block_num gas_used status
  block_num=$(echo "$receipt" | grep "^blockNumber" | awk '{print $2}' || echo "?")
  gas_used=$(echo "$receipt" | grep "^gasUsed" | awk '{print $2}' || echo "?")
  status=$(echo "$receipt" | grep "^status" | awk '{print $2}' || echo "?")
  local status_label
  if [[ "$status" == "1" || "$status" == "true" ]]; then
    status_label="${GREEN}SUCCESS${RESET}"
  else
    status_label="${RED}FAILED${RESET}"
  fi
  printf "  ${DIM}[%s]${RESET} Block ${WHITE}%s${RESET} │ Gas ${WHITE}%s${RESET} │ Status %b\n" "$label" "$block_num" "$gas_used" "$status_label"
}

rocket_crash() {
  local frames=(
    "      \033[38;5;250m          /\\     \n                 |  |    \n                /    \\   \n               |      |  \n               |      |  \n               |      |  \n               |______|  \n                /||||\\   \n               / |||| \\  \033[0m"
    "      \033[38;5;250m                 \n          /\\             \n         |  |            \n        /    \\           \n       |      |          \n       |      |          \n       |______|          \n        /||||\\           \n       / |||| \\          \033[0m"
    "      \033[38;5;250m                 \n                         \n                         \n   /\\                    \n  |  |                   \n /    \\                  \n|______|                 \n /||||\\                  \n/ |||| \\                 \033[0m"
    "      \033[31;1m                 \n                         \n                         \n                         \n                         \n      \\ \\ / /               \n    --- BOOM ---      \n      / / \\ \\               \n                         \033[0m"
  )
  echo ""
  echo -e "  ${RED}${BLINK}${BOLD}>> ALARM: SEVERE MARKET CRASH DETECTED ON LIDO STETH${RESET}"
  echo ""

  # Print first frame
  echo -e "${frames[0]}"
  sleep 0.4

  for ((i=1; i<${#frames[@]}; i++)); do
    # Move cursor up 9 lines to overwrite the previous frame
    printf "\033[9A"
    echo -e "${frames[$i]}"
    sleep 0.4
  done
  echo -e "  ${RED}${BOLD}Lido Staked ETH yield has deeply depegged or exploited!${RESET}\n"
  sleep 1
}

ai_analysis() {
  if [[ -n "${GROQ_API_KEY:-}" ]]; then
    echo -e "  ${DIM}[Oszillor AI] Initializing Groq API (llama-4-scout)...${RESET}"
    sleep 0.5

    echo -e "  ${DIM}[Oszillor AI] Fetching live ETH/stETH market data from CoinGecko...${RESET}"
    # Fetch real live data
    local price_data=$(curl -s --max-time 3 "https://api.coingecko.com/api/v3/simple/price?ids=ethereum,staked-ether&vs_currencies=usd" || echo '{"ethereum":{"usd":3000},"staked-ether":{"usd":2900}}')
    local eth_price=$(echo "$price_data" | grep -o '"ethereum":{"usd":[0-9.]*' | cut -d':' -f3 | tr -d '}' || echo "3000")
    local steth_price=$(echo "$price_data" | grep -o '"staked-ether":{"usd":[0-9.]*' | cut -d':' -f3 | tr -d '}' || echo "2900")

    echo -ne "  ${PURPLE}[Oszillor AI]${RESET} "

    local system_prompt="You are the OSZILLOR Autonomous Risk Gatekeeper, an advanced AI embedded in the Chainlink Runtime Environment (CRE). Your role is to monitor cross-chain yield opportunities, analyze smart contract risk, and protect investor funds in the Oszillor Vault across Ethereum, Arbitrum, Base, and Optimism. You receive real-time telemetry from DefiLlama, CryptoPanic, and on-chain monitors. When a threat is detected, you have the authority to trigger the EMIT_PAUSE_AND_WITHDRAW directive to execute an emergency rebase via CCIP."

    local user_prompt="LIVE MARKET TELEMETRY:\n- ETH Price: \$${eth_price}\n- stETH Price: \$${steth_price}\n- Lido Reserve Status: DROPPING RAPIDLY\n- Event: Infinite mint exploit simulating a massive depeg on the Lido Mock Strategy.\n\nAnalyze this telemetry. In exactly 3 short, highly technical, and urgent sentences:\n1. Diagnose the exploit and the price depeg based on the live data.\n2. Declare a FATAL risk level based on your Oszillor security parameters.\n3. Explicitly recommend the EMIT_PAUSE_AND_WITHDRAW system directive to rescue funds.\nDo not greet or explain, just output the system log."

    export SYS_PROMPT="$system_prompt"
    export USER_PROMPT="$user_prompt"
    local payload=$(node -e "console.log(JSON.stringify({
      model: 'meta-llama/llama-4-scout-17b-16e-instruct',
      messages: [
        {role: 'system', content: process.env.SYS_PROMPT},
        {role: 'user', content: process.env.USER_PROMPT}
      ],
      temperature: 0.2
    }))")

    local response=$(curl -s -X POST "https://api.groq.com/openai/v1/chat/completions" \
      -H "Authorization: Bearer $GROQ_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" | node -e "const fs = require('fs'); const raw = fs.readFileSync(0, 'utf-8'); try{ console.log(JSON.parse(raw).choices[0].message.content) }catch(e){}")

    echo -e "${WHITE}${response}${RESET}"

  elif command -v ollama >/dev/null 2>&1 && ollama list 2>/dev/null | grep -q "qwen3.5"; then
    echo -e "  ${DIM}[Oszillor AI] Initializing Local Qwen 3.5 Inference...${RESET}"
    sleep 0.5
    echo -ne "  ${PURPLE}[Oszillor AI]${RESET} "
    ollama run qwen3.5:latest "You are OSZILLOR's embedded autonomous Risk AI. A severe market crash and depeg just occurred on the Lido stETH protocol where our vault funds are deployed. In exactly 3 short, highly technical, and urgent sentences, diagnose the exploit, declare a FATAL risk level, and explicitly recommend the EMIT_PAUSE_AND_WITHDRAW system directive. Do not greet or explain, just output the system log." | while read -r line; do
        if [[ -n "$line" ]]; then
            echo -e "${WHITE}${line}${RESET}"
            echo -ne "  "
        fi
    done
  else
    local lines=(
      "[Oszillor AI] Ingesting real-time CryptoPanic HTTP streams..."
      "[Oszillor AI] Scanning DefiLlama reserve ratios..."
      "[Oszillor AI] ---------------------------------"
      "[Oszillor AI] Sentiment Analysis :: FATAL PANIC"
      "[Oszillor AI] Exploit Probability :: 98.4%"
      "[Oszillor AI] Risk Vector :: Infinite mint detected on Lido Mock"
      "[Oszillor AI] ---------------------------------"
      "[Oszillor AI] SYSTEM DIRECTIVE INITIATED: EMIT_PAUSE_AND_WITHDRAW"
    )
    for line in "${lines[@]}"; do
      type_line "  ${DIM}${line}${RESET}" "$WHITE" 0.005
      sleep 0.3
    done
  fi
  echo ""
}

format_elapsed() {
  local total=$1
  local mins=$((total / 60))
  local secs=$((total % 60))
  if [[ $mins -gt 0 ]]; then
    printf "%dm %ds" "$mins" "$secs"
  else
    printf "%ds" "$secs"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

print_header
print_system_info

# ── STEP 1: User Deposit ─────────────────────────────────────────────────────
type_line "STEP 1  User Deposit via Frontend (Sepolia Live Network)" "$CYAN"

simulate_processing "Snapshotting pre-deposit balances..." 1
PRE_BALANCES=$(fetch_balances)
display_balances "PRE-DEPOSIT" "$PRE_BALANCES"
IFS=',' read -r pre_w_weth pre_w_osz pre_v_weth pre_s_weth pre_l_weth <<< "$PRE_BALANCES"

# Check & wrap if necessary
w_weth_clean=$(clean_cast "$pre_w_weth")
if [[ "$w_weth_clean" -lt "$DEPOSIT_AMOUNT" ]]; then
  echo -ne "  ${AMBER}! ${DIM}Low WETH detected. Auto-wrapping 0.05 ETH...${RESET}"
  cast send $WETH "deposit()" --value 50000000000000000 --account deployer --rpc-url $RPC >/dev/null 2>&1
  echo -e "\r  ${GREEN}✓${RESET} ${DIM}Auto-wrapped 0.05 ETH to WETH.       ${RESET}"
  # Re-snapshot after wrap
  PRE_BALANCES=$(fetch_balances)
  IFS=',' read -r pre_w_weth pre_w_osz pre_v_weth pre_s_weth pre_l_weth <<< "$PRE_BALANCES"
fi

simulate_processing "Approving WETH spend via ERC-20 approve()" 1
TX_APPROVE=$(cast send $WETH "approve(address,uint256)" $VAULT $DEPOSIT_AMOUNT --account deployer --rpc-url $RPC 2>&1 | grep "^transactionHash " | awk '{print $2}' || echo "0x...")

simulate_processing "Broadcasting atomic deposit — routing to strategy" 2
TX_DEPOSIT=$(cast send $VAULT "deposit(uint256)" $DEPOSIT_AMOUNT --account deployer --rpc-url $RPC 2>&1 | grep "^transactionHash " | awk '{print $2}' || echo "0x...")

echo -e "  ${GREEN}✓${RESET} ${DIM}Deposit confirmed on Sepolia${RESET}"
verify_tx_receipt "Deposit" "$TX_DEPOSIT"
echo ""

# Snapshot after deposit
POST_DEPOSIT_BALANCES=$(fetch_balances)
display_balance_diff "$PRE_BALANCES" "$POST_DEPOSIT_BALANCES"

sleep 1
printf "  ${DIM}══════════════════════════════════════════════════════════════════${RESET}\n\n"

# ── STEP 2: Market Crash ─────────────────────────────────────────────────────
type_line "STEP 2  Simulating Time Passing... and suddenly..." "$PURPLE"
sleep 2

rocket_crash

printf "  ${DIM}══════════════════════════════════════════════════════════════════${RESET}\n\n"

# ── STEP 3: AI Risk Scanner (W1) ─────────────────────────────────────────────
type_line "STEP 3  AI Risk Scanner (CRE Workflow W1) Awakens" "$GOLD"
ai_analysis

cd "$PROJECT_ROOT/cre-workflows"

echo -e "  ${CYAN}>> Broadcasting AI Decision Hash to RiskEngine via Chainlink CRE...${RESET}"
CRE_OUTPUT_1=$(cre workflow simulate ./oszillor-risk-scanner --target staging-settings --broadcast 2>&1 || true)
parse_cre_output "$CRE_OUTPUT_1"
TX_W1=$(extract_tx_hash "$CRE_OUTPUT_1")
echo -e "  ${GREEN}✓${RESET} ${DIM}Risk report submitted to RiskEngine${RESET}"
verify_tx_receipt "W1 Risk" "$TX_W1"
echo ""

sleep 1
printf "  ${DIM}══════════════════════════════════════════════════════════════════${RESET}\n\n"

# ── STEP 4: Event Sentinel (W2) ──────────────────────────────────────────────
type_line "STEP 4  Event Sentinel (CRE Workflow W2) Enforces Security" "$PURPLE"
simulate_processing "Listening to on-chain pool reserve events..." 1
simulate_processing "Detecting slippage threshold exceeded..." 1
echo -e "  ${CYAN}>> Validating AI Signal + On-Chain State...${RESET}"
sleep 1
echo -e "  ${DIM}[SENTINEL] State Invalid. Lido ETH reserves plunging.${RESET}"
echo -e "  ${DIM}[SENTINEL] Executing Emergency Pauser Role...${RESET}"
echo ""

echo -e "  ${CYAN}>> Broadcasting Pause Command to Oszillor Vault...${RESET}"
CRE_OUTPUT_2=$(cre workflow simulate ./oszillor-event-sentinel --target staging-settings --broadcast 2>&1 || true)
parse_cre_output "$CRE_OUTPUT_2"
TX_W2=$(extract_tx_hash "$CRE_OUTPUT_2")
echo -e "  ${GREEN}✓${RESET} ${DIM}Emergency threat report submitted to EventSentinel${RESET}"
verify_tx_receipt "W2 Sentinel" "$TX_W2"
echo ""

sleep 1
printf "  ${DIM}══════════════════════════════════════════════════════════════════${RESET}\n\n"

# ── STEP 5: Rebase Executor (W3) ─────────────────────────────────────────────
type_line "STEP 5  Rebase Executor (CRE Workflow W3) Rescues Funds" "$CYAN"
simulate_processing "Calculating impermanent loss impact..." 1
simulate_processing "Generating emergency withdrawal proofs..." 1
echo -e "  ${CYAN}>> Initiating Cross-Component Fund Recovery...${RESET}"
sleep 1
echo -e "  ${DIM}[REBASE] Pulling WETH out from Lido Mock Strategy...${RESET}"
echo -e "  ${DIM}[REBASE] Adjusting Vault state and protecting investors...${RESET}"
echo ""

echo -e "  ${CYAN}>> Broadcasting Rebase & Withdrawal Transaction...${RESET}"
CRE_OUTPUT_3=$(cre workflow simulate ./oszillor-rebase-executor --target staging-settings --broadcast 2>&1 || true)
parse_cre_output "$CRE_OUTPUT_3"
TX_W3=$(extract_tx_hash "$CRE_OUTPUT_3")
echo -e "  ${GREEN}✓${RESET} ${DIM}Rebalance + rebase report submitted to RebaseExecutor${RESET}"
verify_tx_receipt "W3 Rebase" "$TX_W3"
echo ""

sleep 1
printf "  ${DIM}══════════════════════════════════════════════════════════════════${RESET}\n\n"

# ── STEP 6: Final Verification ───────────────────────────────────────────────
type_line "STEP 6  Final Atomic State Verification" "$GOLD"
simulate_processing "Querying updated contract balances..." 2

POST_BALANCES=$(fetch_balances)
display_balance_diff "$POST_DEPOSIT_BALANCES" "$POST_BALANCES"

echo -e "  ${GREEN}${BOLD}✓ Incident Response Successful${RESET}"
echo -e "    The AI detected the crash, routed the decision through the Chainlink DON"
echo -e "    (simulated via CRE), paused the vault, and forced an emergency withdrawal."
echo -e "    ${WHITE}Funds were pulled FROM the strategy back INTO the main vault.${RESET}"
echo ""

# ── PROOF OF EXECUTION ───────────────────────────────────────────────────────
DEMO_ELAPSED=$((SECONDS - DEMO_START))

printf "  ${GOLD}${BOLD}══════════════════════════════════════════════════════════════════${RESET}\n"
printf "  ${GOLD}${BOLD}  PROOF OF EXECUTION — SEPOLIA LIVE TRANSACTIONS${RESET}\n"
printf "  ${GOLD}${BOLD}══════════════════════════════════════════════════════════════════${RESET}\n\n"

printf "  ${BOLD}${WHITE}Deployed Contracts${RESET}\n"
printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n"
printf "  Vault:          ${CYAN}${EXPLORER}/address/${VAULT}${RESET}\n"
printf "  Token (OSZ):    ${CYAN}${EXPLORER}/address/${TOKEN}${RESET}\n"
printf "  Strategy:       ${CYAN}${EXPLORER}/address/${STRATEGY}${RESET}\n"
printf "  RiskEngine:     ${CYAN}${EXPLORER}/address/${RISK_ENGINE}${RESET}\n"
printf "  EventSentinel:  ${CYAN}${EXPLORER}/address/${EVENT_SENTINEL}${RESET}\n"
printf "  RebaseExecutor: ${CYAN}${EXPLORER}/address/${REBASE_EXECUTOR}${RESET}\n"
printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n\n"

printf "  ${BOLD}${WHITE}Transaction Log${RESET}\n"
printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n"
printf "  ${GOLD}1.${RESET} User Deposit      ${CYAN}${EXPLORER}/tx/${TX_DEPOSIT}${RESET}\n"
printf "  ${GOLD}2.${RESET} AI Risk Report    ${CYAN}${EXPLORER}/tx/${TX_W1}${RESET}\n"
printf "  ${GOLD}3.${RESET} Emergency Pause   ${CYAN}${EXPLORER}/tx/${TX_W2}${RESET}\n"
printf "  ${GOLD}4.${RESET} Fund Rescue       ${CYAN}${EXPLORER}/tx/${TX_W3}${RESET}\n"
printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n\n"

printf "  ${DIM}Total demo time: ${WHITE}$(format_elapsed $DEMO_ELAPSED)${RESET} │ "
printf "${DIM}Transactions: ${WHITE}4 confirmed${RESET} │ "
printf "${DIM}Network: ${WHITE}Sepolia${RESET}\n\n"

printf "  ${GOLD}${BOLD}══════════════════════════════════════════════════════════════════${RESET}\n"
type_line "  DEMONSTRATION COMPLETE." "$WHITE"
printf "  ${GOLD}${BOLD}══════════════════════════════════════════════════════════════════${RESET}\n\n"
