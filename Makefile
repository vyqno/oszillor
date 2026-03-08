# ═══════════════════════════════════════════════════════════════
#                    OSZILLOR — Makefile
# ═══════════════════════════════════════════════════════════════
#
#  make                   — Show all available commands
#  make test-all          — Run ALL tests (Foundry + CRE W1-W4)
#  make showcase          — Full project showcase (tests + API + simulate)
#  make install-all       — Install ALL dependencies
#
# ═══════════════════════════════════════════════════════════════

# ── Config ──
FORGE     := forge
CAST      := cast
ACCOUNT   := deployer
HUB_RPC   := sepolia
SPOKE_RPC := base_sepolia

# ── Paths ──
CONTRACTS  := contracts
SCRIPTS    := script
CRE_DIR    := cre-workflows
API_DIR    := risk-api
AGENT_DIR  := risk-api/agent
FRONTEND   := frontend

# ═══════════════════════════════════════════════════════════════
#  SETUP & INSTALL
# ═══════════════════════════════════════════════════════════════

.PHONY: setup
setup: ## Initial setup — Foundry deps + deployer keystore
	@echo "═══ Installing Foundry deps ═══"
	cd $(CONTRACTS) && $(FORGE) install
	@echo ""
	@echo "═══ Creating deployer keystore ═══"
	@echo "You will be prompted to enter your private key and set a password."
	$(CAST) wallet import $(ACCOUNT) --interactive
	@echo ""
	@echo "Keystore created. Use --account $(ACCOUNT) with forge script."
	@echo "  Your deployer address:"
	$(CAST) wallet address --account $(ACCOUNT)

.PHONY: install-all
install-all: install-contracts install-cre install-api install-agent install-frontend ## Install ALL project dependencies
	@echo ""
	@echo "All dependencies installed."

.PHONY: install-contracts
install-contracts: ## Install Foundry dependencies
	cd $(CONTRACTS) && $(FORGE) install

.PHONY: install-cre
install-cre: ## Install CRE workflow dependencies (all 4 workflows)
	@echo "═══ Installing CRE W1 deps ═══"
	cd $(CRE_DIR)/oszillor-risk-scanner && bun install
	@echo "═══ Installing CRE W2 deps ═══"
	cd $(CRE_DIR)/oszillor-event-sentinel && bun install
	@echo "═══ Installing CRE W3 deps ═══"
	cd $(CRE_DIR)/oszillor-rebase-executor && bun install
	@echo "═══ Installing CRE W4 deps ═══"
	cd $(CRE_DIR)/oszillor-risk-alerts && bun install

.PHONY: install-api
install-api: ## Install Risk API server dependencies
	cd $(API_DIR) && bun install

.PHONY: install-agent
install-agent: ## Install AI Agent dependencies
	cd $(AGENT_DIR) && bun install

.PHONY: install-frontend
install-frontend: ## Install Frontend dependencies
	cd $(FRONTEND) && bun install

# ═══════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════

.PHONY: build
build: ## Compile all Solidity contracts
	cd $(CONTRACTS) && $(FORGE) build

.PHONY: build-cre
build-cre: ## Compile all 4 CRE workflows to WASM
	@echo "═══ Compiling W1 — Risk Scanner ═══"
	cd $(CRE_DIR)/oszillor-risk-scanner && bun run cre-compile main.ts
	@echo "═══ Compiling W2 — Event Sentinel ═══"
	cd $(CRE_DIR)/oszillor-event-sentinel && bun run cre-compile main.ts
	@echo "═══ Compiling W3 — Rebase Executor ═══"
	cd $(CRE_DIR)/oszillor-rebase-executor && bun run cre-compile main.ts
	@echo "═══ Compiling W4 — Risk Alerts ═══"
	cd $(CRE_DIR)/oszillor-risk-alerts && bun run cre-compile main.ts
	@echo ""
	@echo "All 4 CRE workflows compiled to WASM."

.PHONY: build-all
build-all: build build-cre ## Build everything (Solidity + CRE WASM)
	@echo ""
	@echo "All builds complete."

.PHONY: build-frontend
build-frontend: ## Build frontend for production
	cd $(FRONTEND) && bun run build

# ═══════════════════════════════════════════════════════════════
#  TESTING — Solidity
# ═══════════════════════════════════════════════════════════════

.PHONY: test
test: ## Run all 305 Solidity tests
	cd $(CONTRACTS) && $(FORGE) test

.PHONY: test-v
test-v: ## Run all tests with verbose output (-vvv)
	cd $(CONTRACTS) && $(FORGE) test -vvv

.PHONY: test-summary
test-summary: ## Run all tests with per-suite summary table
	cd $(CONTRACTS) && $(FORGE) test --summary

.PHONY: test-unit
test-unit: ## Run only unit tests
	cd $(CONTRACTS) && $(FORGE) test \
		--match-contract "OszillorVaultTest|OszillorTokenTest|AlertRegistryTest|VaultStrategyTest|ModulesTest|LibrariesTest|OszillorTokenPoolTest|PeersTest"

.PHONY: test-fuzz
test-fuzz: ## Run only fuzz tests (10,000 runs each)
	cd $(CONTRACTS) && $(FORGE) test \
		--match-contract "DepositWithdrawFuzzTest|OszillorTokenFuzzTest|RiskMathFuzzTest|ShareMathFuzzTest"

.PHONY: test-invariant
test-invariant: ## Run only invariant tests (stateful fuzzing)
	cd $(CONTRACTS) && $(FORGE) test --match-contract OszillorInvariantTest -vv

.PHONY: test-integration
test-integration: ## Run only CRE integration tests
	cd $(CONTRACTS) && $(FORGE) test --match-contract CREIntegrationTest -vv

.PHONY: test-vault
test-vault: ## Run OszillorVault tests (64 tests)
	cd $(CONTRACTS) && $(FORGE) test --match-contract OszillorVaultTest -vv

.PHONY: test-token
test-token: ## Run OszillorToken tests (41 tests)
	cd $(CONTRACTS) && $(FORGE) test --match-contract OszillorTokenTest -vv

.PHONY: test-strategy
test-strategy: ## Run VaultStrategy tests (32 tests)
	cd $(CONTRACTS) && $(FORGE) test --match-contract VaultStrategyTest -vv

.PHONY: test-alerts
test-alerts: ## Run AlertRegistry tests (20 tests)
	cd $(CONTRACTS) && $(FORGE) test --match-contract AlertRegistryTest -vv

.PHONY: test-peers
test-peers: ## Run Peers tests (13 tests)
	cd $(CONTRACTS) && $(FORGE) test --match-contract PeersTest -vv

.PHONY: test-pool
test-pool: ## Run TokenPool tests (18 tests)
	cd $(CONTRACTS) && $(FORGE) test --match-contract OszillorTokenPoolTest -vv

.PHONY: test-gas
test-gas: ## Run all tests with gas report
	cd $(CONTRACTS) && $(FORGE) test --gas-report

# ═══════════════════════════════════════════════════════════════
#  TESTING — CRE Workflow Simulations
# ═══════════════════════════════════════════════════════════════

.PHONY: simulate-w1
simulate-w1: ## Simulate W1 Risk Scanner (cron → risk score + AI)
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-risk-scanner --target staging-settings

.PHONY: simulate-w2
simulate-w2: ## Simulate W2 Event Sentinel (cron → crash detection)
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-event-sentinel --target staging-settings

.PHONY: simulate-w3
simulate-w3: ## Simulate W3 Rebase Executor (cron → rebalance)
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-rebase-executor --target staging-settings

.PHONY: simulate-w4-cron
simulate-w4-cron: ## Simulate W4 Risk Alerts — cron trigger (alert evaluation)
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-risk-alerts \
		--target staging-settings --non-interactive --trigger-index 1

.PHONY: simulate-w4-http
simulate-w4-http: ## Simulate W4 Risk Alerts — HTTP trigger (alert creation)
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-risk-alerts \
		--target staging-settings --non-interactive --trigger-index 0 \
		--http-payload '{"subscriber":"0x814a3D96C36C45e92159Ce119a82b3250Aa79E5b","condition":0,"threshold":70,"webhookUrl":"https://example.com/alert","ttl":86400}'

.PHONY: simulate-all
simulate-all: simulate-w1 simulate-w2 simulate-w3 simulate-w4-cron ## Simulate all 4 CRE workflows sequentially
	@echo ""
	@echo "All 4 CRE workflow simulations complete."

# ═══════════════════════════════════════════════════════════════
#  TESTING — Combined
# ═══════════════════════════════════════════════════════════════

.PHONY: test-all
test-all: test-summary simulate-all ## Run ALL tests (305 Foundry + 4 CRE simulations)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  ALL TESTS PASSED"
	@echo "  Foundry: 305 tests (unit + fuzz + invariant)"
	@echo "  CRE:     4 workflow simulations (W1-W4)"
	@echo "══════════════════════════════════════════════"

# ═══════════════════════════════════════════════════════════════
#  x402 RISK API
# ═══════════════════════════════════════════════════════════════

.PHONY: api-start
api-start: ## Start Risk API server (port 4021)
	cd $(API_DIR) && bun run start

.PHONY: api-dev
api-dev: ## Start Risk API server with hot reload
	cd $(API_DIR) && bun run dev

.PHONY: api-test
api-test: ## Test all 6 API endpoints (server must be running)
	@echo "═══ Testing Risk API Endpoints ═══"
	@echo ""
	@echo "GET /health (free):"
	@curl -s http://localhost:4021/health | head -c 200
	@echo ""
	@echo ""
	@echo "GET /v1/risk/current (expects 402):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:4021/v1/risk/current
	@echo "GET /v1/risk/portfolio (expects 402):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:4021/v1/risk/portfolio
	@echo "GET /v1/risk/full (expects 402):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:4021/v1/risk/full
	@echo "POST /v1/alerts (expects 402):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" -X POST http://localhost:4021/v1/alerts \
		-H "Content-Type: application/json" \
		-d '{"subscriber":"0x1234","condition":"RISK_ABOVE","threshold":70}'
	@echo "GET /v1/alerts/1 (expects 402 or 404):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:4021/v1/alerts/1
	@echo ""
	@echo "API endpoint test complete."

.PHONY: api-demo
api-demo: ## Run lightweight x402 payment demo (needs EVM_PRIVATE_KEY)
	cd $(API_DIR) && bun run demo

# ═══════════════════════════════════════════════════════════════
#  AI AGENT (Coinbase AgentKit + Claude)
# ═══════════════════════════════════════════════════════════════

.PHONY: agent-chat
agent-chat: ## Start AI agent — interactive chat mode
	cd $(AGENT_DIR) && bun run start

.PHONY: agent-auto
agent-auto: ## Start AI agent — autonomous risk monitoring
	cd $(AGENT_DIR) && bun run auto

# ═══════════════════════════════════════════════════════════════
#  FRONTEND
# ═══════════════════════════════════════════════════════════════

.PHONY: frontend-dev
frontend-dev: ## Start Next.js frontend dev server (port 3000)
	cd $(FRONTEND) && bun run dev

.PHONY: frontend-build
frontend-build: ## Build frontend for production
	cd $(FRONTEND) && bun run build

.PHONY: frontend-start
frontend-start: ## Start production frontend server
	cd $(FRONTEND) && bun run start

.PHONY: frontend-lint
frontend-lint: ## Lint frontend code
	cd $(FRONTEND) && bun run lint

# ═══════════════════════════════════════════════════════════════
#  DEPLOYMENT
# ═══════════════════════════════════════════════════════════════

.PHONY: deploy-hub
deploy-hub: ## Deploy hub contracts to Ethereum Sepolia
	@echo "═══ Deploying OSZILLOR Hub to Sepolia ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployHub.s.sol:DeployHub \
		--rpc-url $(HUB_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		--broadcast \
		-vvvv

.PHONY: deploy-hub-dry
deploy-hub-dry: ## Dry run hub deployment (no broadcast)
	@echo "═══ Dry Run: OSZILLOR Hub ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployHub.s.sol:DeployHub \
		--rpc-url $(HUB_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		-vvvv

.PHONY: deploy-alerts
deploy-alerts: ## Deploy AlertRegistry to Base Sepolia (W4)
	@echo "═══ Deploying AlertRegistry to Base Sepolia ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployAlertRegistry.s.sol:DeployAlertRegistry \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		--broadcast \
		-vvvv

.PHONY: deploy-alerts-dry
deploy-alerts-dry: ## Dry run AlertRegistry deployment (no broadcast)
	@echo "═══ Dry Run: AlertRegistry (Base Sepolia) ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployAlertRegistry.s.sol:DeployAlertRegistry \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		-vvvv

.PHONY: deploy-spoke
deploy-spoke: ## Deploy spoke contracts to Base Sepolia
	@echo "═══ Deploying OSZILLOR Spoke to Base Sepolia ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeploySpoke.s.sol:DeploySpoke \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--broadcast \
		-vvvv

.PHONY: deploy-spoke-dry
deploy-spoke-dry: ## Dry run spoke deployment (no broadcast)
	@echo "═══ Dry Run: OSZILLOR Spoke ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeploySpoke.s.sol:DeploySpoke \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		-vvvv

.PHONY: roles
roles: ## Setup operational roles (run after deploy-hub)
	@echo "═══ Setting up roles ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/interactions/SetupRoles.s.sol:SetupRoles \
		--rpc-url $(HUB_RPC) \
		--account $(ACCOUNT) \
		--broadcast \
		-vvvv

.PHONY: validate
validate: ## Validate deployment (read-only, no broadcast)
	@echo "═══ Validating deployment ═══"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/interactions/ValidateDeployment.s.sol:ValidateDeployment \
		--rpc-url $(HUB_RPC) \
		-vvvv

.PHONY: deploy-base
deploy-base: ## Deploy ALL contracts to Base Sepolia (hub + alerts)
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║     Deploying ALL OSZILLOR contracts to Base Sepolia    ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "━━━ Step 1/3: Hub Contracts (Token, Strategy, Vault, CRE, CCIP) ━━━"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployHub.s.sol:DeployHub \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		--broadcast \
		-vvvv
	@echo ""
	@echo "━━━ Step 2/3: AlertRegistry (W4 CRE receiver) ━━━"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployAlertRegistry.s.sol:DeployAlertRegistry \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		--broadcast \
		-vvvv
	@echo ""
	@echo "━━━ Step 3/3: Role Setup ━━━"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/interactions/SetupRoles.s.sol:SetupRoles \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--broadcast \
		-vvvv
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║          Base Sepolia Deployment Complete!               ║"
	@echo "║                                                         ║"
	@echo "║  Update contracts/.env with the deployed addresses      ║"
	@echo "║  Update risk-api/.env with VAULT_ADDRESS + STRATEGY     ║"
	@echo "║  Update cre-workflows config with AlertRegistry addr    ║"
	@echo "╚══════════════════════════════════════════════════════════╝"

.PHONY: deploy-base-dry
deploy-base-dry: ## Dry run full Base Sepolia deployment (no broadcast)
	@echo "═══ Dry Run: Full Base Sepolia Deployment ═══"
	@echo ""
	@echo "━━━ Hub Contracts ━━━"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployHub.s.sol:DeployHub \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		-vvvv
	@echo ""
	@echo "━━━ AlertRegistry ━━━"
	cd $(CONTRACTS) && $(FORGE) script $(SCRIPTS)/deploy/DeployAlertRegistry.s.sol:DeployAlertRegistry \
		--rpc-url $(SPOKE_RPC) \
		--account $(ACCOUNT) \
		--sender "$$(awk -F= '/^DEPLOYER_ADDRESS=/{print $$2}' .env)" \
		-vvvv

.PHONY: deploy-all
deploy-all: deploy-hub roles validate ## Full hub pipeline: deploy + roles + validate (Eth Sepolia)
	@echo ""
	@echo "═══ Full Hub Deployment Pipeline Complete ═══"

# ═══════════════════════════════════════════════════════════════
#  E2E DEMO
# ═══════════════════════════════════════════════════════════════

.PHONY: demo-e2e
demo-e2e: ## Run full E2E demo on Base Sepolia (default, live transactions)
	bash demo/e2e-master.sh --chain base-sepolia

.PHONY: demo-e2e-sepolia
demo-e2e-sepolia: ## Run full E2E demo on Eth Sepolia (live transactions)
	bash demo/e2e-master.sh --chain sepolia

# ═══════════════════════════════════════════════════════════════
#  SHOWCASE — Full Project Demo
# ═══════════════════════════════════════════════════════════════

.PHONY: showcase
showcase: ## Full project showcase — tests + CRE simulations + API check
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║           OSZILLOR — Full Project Showcase              ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "━━━ STEP 1/3: Solidity Tests (305 tests) ━━━"
	cd $(CONTRACTS) && $(FORGE) test --summary
	@echo ""
	@echo "━━━ STEP 2/3: CRE Workflow Simulations (W1-W4) ━━━"
	@echo ""
	@echo "── W1 Risk Scanner ──"
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-risk-scanner --target staging-settings
	@echo ""
	@echo "── W2 Event Sentinel ──"
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-event-sentinel --target staging-settings
	@echo ""
	@echo "── W3 Rebase Executor ──"
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-rebase-executor --target staging-settings
	@echo ""
	@echo "── W4 Risk Alerts (cron trigger) ──"
	cd $(CRE_DIR) && cre workflow simulate ./oszillor-risk-alerts \
		--target staging-settings --non-interactive --trigger-index 1
	@echo ""
	@echo "━━━ STEP 3/3: Build Verification ━━━"
	cd $(CONTRACTS) && $(FORGE) build --sizes 2>&1 | head -25
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║                  SHOWCASE COMPLETE                      ║"
	@echo "║                                                         ║"
	@echo "║  Foundry:  305/305 tests passed                         ║"
	@echo "║  CRE:      4/4 workflows simulated                      ║"
	@echo "║  Solidity: All contracts compiled                        ║"
	@echo "║                                                         ║"
	@echo "║  To run the API:    make api-dev                        ║"
	@echo "║  To test the API:   make api-test                       ║"
	@echo "║  To run the agent:  make agent-chat                     ║"
	@echo "║  To run frontend:   make frontend-dev                   ║"
	@echo "╚══════════════════════════════════════════════════════════╝"

# ═══════════════════════════════════════════════════════════════
#  UTILITIES
# ═══════════════════════════════════════════════════════════════

.PHONY: clean
clean: ## Clean Foundry build artifacts
	cd $(CONTRACTS) && $(FORGE) clean

.PHONY: snapshot
snapshot: ## Create gas snapshot
	cd $(CONTRACTS) && $(FORGE) snapshot

.PHONY: fmt
fmt: ## Format Solidity files
	cd $(CONTRACTS) && $(FORGE) fmt

.PHONY: sizes
sizes: ## Show contract deployment sizes
	cd $(CONTRACTS) && $(FORGE) build --sizes

.PHONY: status
status: ## Show project status (git + deps + build health)
	@echo "═══ Git Status ═══"
	@git status --short
	@echo ""
	@echo "═══ Foundry Build ═══"
	@cd $(CONTRACTS) && $(FORGE) build --silent 2>&1 && echo "  Solidity: OK" || echo "  Solidity: FAIL"
	@echo ""
	@echo "═══ CRE Workflows ═══"
	@test -f $(CRE_DIR)/oszillor-risk-scanner/main.wasm && echo "  W1: compiled" || echo "  W1: not compiled (run make build-cre)"
	@test -f $(CRE_DIR)/oszillor-event-sentinel/main.wasm && echo "  W2: compiled" || echo "  W2: not compiled"
	@test -f $(CRE_DIR)/oszillor-rebase-executor/main.wasm && echo "  W3: compiled" || echo "  W3: not compiled"
	@test -f $(CRE_DIR)/oszillor-risk-alerts/main.wasm && echo "  W4: compiled" || echo "  W4: not compiled"
	@echo ""
	@echo "═══ Node Dependencies ═══"
	@test -d $(API_DIR)/node_modules && echo "  Risk API: installed" || echo "  Risk API: not installed (run make install-api)"
	@test -d $(AGENT_DIR)/node_modules && echo "  Agent:    installed" || echo "  Agent:    not installed (run make install-agent)"
	@test -d $(FRONTEND)/node_modules && echo "  Frontend: installed" || echo "  Frontend: not installed (run make install-frontend)"

# ═══════════════════════════════════════════════════════════════
#  HELP
# ═══════════════════════════════════════════════════════════════

.PHONY: help
help: ## Show all available commands
	@echo ""
	@echo "  OSZILLOR — Available Commands"
	@echo "  ─────────────────────────────────────────────────────"
	@echo ""
	@echo "  Setup & Install:"
	@grep -E '^(setup|install)[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Build:"
	@grep -E '^build[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Test — Solidity:"
	@grep -E '^test[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Test — CRE Workflows:"
	@grep -E '^simulate-[a-zA-Z_0-9-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  x402 Risk API:"
	@grep -E '^api[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  AI Agent:"
	@grep -E '^agent[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Frontend:"
	@grep -E '^frontend[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Deploy:"
	@grep -E '^(deploy|roles|validate)[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Demo & Showcase:"
	@grep -E '^(deploy-base|demo-|showcase)[a-zA-Z_0-9-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Utilities:"
	@grep -E '^(clean|snapshot|fmt|sizes|status):.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
