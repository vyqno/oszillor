# ═══════════════════════════════════════════════════════════════
#                    OSZILLOR — Makefile
# ═══════════════════════════════════════════════════════════════
# Usage:
#   make setup        — Install deps + create deployer keystore
#   make build        — Compile contracts
#   make test         — Run all tests
#   make deploy-hub   — Deploy hub contracts to Sepolia
#   make deploy-spoke — Deploy spoke contracts to Base Sepolia
#   make roles        — Run post-deploy role setup
#   make validate     — Run post-deploy validation
# ═══════════════════════════════════════════════════════════════

# ── Config ──
FORGE     := forge
CAST      := cast
ACCOUNT   := deployer
HUB_RPC   := sepolia
SPOKE_RPC := base_sepolia

# ── Paths ──
CONTRACTS := contracts
SCRIPTS   := script

# ═══════════════════ Setup ═══════════════════

.PHONY: setup
setup: ## Install dependencies + create deployer keystore
	@echo "═══ Installing Foundry deps ═══"
	cd $(CONTRACTS) && $(FORGE) install
	@echo ""
	@echo "═══ Creating deployer keystore ═══"
	@echo "You will be prompted to enter your private key and set a password."
	$(CAST) wallet import $(ACCOUNT) --interactive
	@echo ""
	@echo "✓ Keystore created. Use --account $(ACCOUNT) with forge script."
	@echo "  Your deployer address:"
	$(CAST) wallet address --account $(ACCOUNT)

# ═══════════════════ Build & Test ═══════════════════

.PHONY: build
build: ## Compile all contracts
	cd $(CONTRACTS) && $(FORGE) build

.PHONY: test
test: ## Run all Solidity tests
	cd $(CONTRACTS) && $(FORGE) test

.PHONY: test-v
test-v: ## Run all tests with verbose output
	cd $(CONTRACTS) && $(FORGE) test -vvv

.PHONY: test-peers
test-peers: ## Run only Peers tests
	cd $(CONTRACTS) && $(FORGE) test --match-contract PeersTest -vv

.PHONY: test-invariant
test-invariant: ## Run only invariant tests
	cd $(CONTRACTS) && $(FORGE) test --match-contract OszillorInvariantTest -vv

.PHONY: test-gas
test-gas: ## Run tests with gas report
	cd $(CONTRACTS) && $(FORGE) test --gas-report

# ═══════════════════ Deploy ═══════════════════

.PHONY: deploy-hub
deploy-hub: ## Deploy hub contracts to Sepolia
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

# ═══════════════════ Post-Deploy ═══════════════════

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

# ═══════════════════ Full Pipeline ═══════════════════

.PHONY: deploy-all
deploy-all: deploy-hub roles validate ## Deploy hub + setup roles + validate
	@echo ""
	@echo "═══ Full Hub Deployment Pipeline Complete ═══"
	@echo "Next: make deploy-spoke (after updating .env with spoke addresses)"

# ═══════════════════ Utilities ═══════════════════

.PHONY: clean
clean: ## Clean build artifacts
	cd $(CONTRACTS) && $(FORGE) clean

.PHONY: snapshot
snapshot: ## Create gas snapshot
	cd $(CONTRACTS) && $(FORGE) snapshot

.PHONY: fmt
fmt: ## Format Solidity files
	cd $(CONTRACTS) && $(FORGE) fmt

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
