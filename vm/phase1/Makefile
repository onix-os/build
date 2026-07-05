# ONIX Phase 1 — first real ONIX stones.
.DEFAULT_GOAL := help

PHASE0 := ../phase0
BUILD_USER ?= mason
export BUILD_USER

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-1 1 100 101 102 check ready branding filesystem filesystem-only

help: ## show Phase 1 help
	@echo "ONIX Phase 1 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 1\033[0m    run all Phase 1 steps: 100..102\n"
	@printf "  \033[36mmake phase 100\033[0m  verify Phase 1 forge readiness\n"
	@printf "  \033[36mmake phase 101\033[0m  build/check/install first real ONIX stone: onix-branding\n"
	@printf "  \033[36mmake phase 102\033[0m  build/check/install onix-filesystem with onix-branding\n"

phase: ## run a Phase 1 learning alias
	@case "$(PHASE_ARG)" in \
	  1) $(MAKE) --no-print-directory phase-1 ;; \
	  100) $(MAKE) --no-print-directory ready ;; \
	  101) $(MAKE) --no-print-directory branding ;; \
	  102) $(MAKE) --no-print-directory filesystem ;; \
	  *) echo "unknown Phase 1 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

1 100 101 102:
	@:

phase-1: ## run every Phase 1 step in order
	@set -e; \
	for phase in 100 101; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done; \
	echo; \
	echo "==> make phase 102"; \
	$(MAKE) --no-print-directory filesystem-only

check: ## host-side syntax validation only
	@bash -n build-branding-stone.sh build-filesystem-stone.sh
	@echo "phase1   : check OK"

ready: ## verify the running forge has boulder+moss available
	$(PHASE0)/ssh.sh $(BUILD_USER) 'export PATH="$$HOME/.local/bin:$$PATH"; command -v moss; moss --version; command -v boulder; boulder --version'

branding: ## build/check/install onix-branding in the running forge
	./build-branding-stone.sh

filesystem: branding ## build/check/install onix-filesystem composed with branding
	./build-filesystem-stone.sh

filesystem-only:
	./build-filesystem-stone.sh
