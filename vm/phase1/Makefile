# ONIX Phase 1 — first real ONIX stones.
.DEFAULT_GOAL := help

PHASE0 := ../phase0
BUILD_USER ?= mason
export BUILD_USER

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-1 1 100 101 102 103 104 105 106 107 108 check ready branding filesystem filesystem-only local-repo local-repo-only publishable-repo publishable-repo-only export-publishable-repo export-publishable-repo-only verify-exported-repo publish-plan publish-dry-run

help: ## show Phase 1 help
	@echo "ONIX Phase 1 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 1\033[0m    run all Phase 1 steps: 100..108\n"
	@printf "  \033[36mmake phase 100\033[0m  verify Phase 1 forge readiness\n"
	@printf "  \033[36mmake phase 101\033[0m  build/check/install first real ONIX stone: onix-branding\n"
	@printf "  \033[36mmake phase 102\033[0m  build/check/install onix-filesystem with onix-branding\n"
	@printf "  \033[36mmake phase 103\033[0m  assemble first named local ONIX repo and install from it\n"
	@printf "  \033[36mmake phase 104\033[0m  prepare publishable ONIX repo layout and verify it\n"
	@printf "  \033[36mmake phase 105\033[0m  export publishable ONIX repo from forge to host artifacts\n"
	@printf "  \033[36mmake phase 106\033[0m  verify exported host ONIX repo artifact\n"
	@printf "  \033[36mmake phase 107\033[0m  verify no-upload ONIX repo publishing plan\n"
	@printf "  \033[36mmake phase 108\033[0m  preview repo publication without upload/network\n"

phase: ## run a Phase 1 learning alias
	@case "$(PHASE_ARG)" in \
	  1) $(MAKE) --no-print-directory phase-1 ;; \
	  100) $(MAKE) --no-print-directory ready ;; \
	  101) $(MAKE) --no-print-directory branding ;; \
	  102) $(MAKE) --no-print-directory filesystem ;; \
	  103) $(MAKE) --no-print-directory local-repo ;; \
	  104) $(MAKE) --no-print-directory publishable-repo ;; \
	  105) $(MAKE) --no-print-directory export-publishable-repo ;; \
	  106) $(MAKE) --no-print-directory verify-exported-repo ;; \
	  107) $(MAKE) --no-print-directory publish-plan ;; \
	  108) $(MAKE) --no-print-directory publish-dry-run ;; \
	  *) echo "unknown Phase 1 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

1 100 101 102 103 104 105 106 107 108:
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
	$(MAKE) --no-print-directory filesystem-only; \
	echo; \
	echo "==> make phase 103"; \
	$(MAKE) --no-print-directory local-repo-only; \
	echo; \
	echo "==> make phase 104"; \
	$(MAKE) --no-print-directory publishable-repo-only; \
	echo; \
	echo "==> make phase 105"; \
	$(MAKE) --no-print-directory export-publishable-repo-only; \
	echo; \
	echo "==> make phase 106"; \
	$(MAKE) --no-print-directory verify-exported-repo; \
	echo; \
	echo "==> make phase 107"; \
	$(MAKE) --no-print-directory publish-plan; \
	echo; \
	echo "==> make phase 108"; \
	$(MAKE) --no-print-directory publish-dry-run

check: ## host-side syntax validation only
	@bash -n build-branding-stone.sh build-filesystem-stone.sh build-local-repo.sh build-publishable-repo.sh export-publishable-repo.sh verify-exported-repo.sh prepare-publish-plan.sh publish-dry-run.sh
	@echo "phase1   : check OK"

ready: ## verify the running forge has boulder+moss available
	$(PHASE0)/ssh.sh $(BUILD_USER) 'export PATH="$$HOME/.local/bin:$$PATH"; command -v moss; moss --version; command -v boulder; boulder --version'

branding: ## build/check/install onix-branding in the running forge
	./build-branding-stone.sh

filesystem: branding ## build/check/install onix-filesystem composed with branding
	./build-filesystem-stone.sh

filesystem-only:
	./build-filesystem-stone.sh

local-repo: ## assemble named local ONIX repo and install from it
	./build-local-repo.sh

local-repo-only:
	./build-local-repo.sh

publishable-repo: ## prepare publishable ONIX repo layout and verify it
	./build-publishable-repo.sh

publishable-repo-only:
	./build-publishable-repo.sh

export-publishable-repo: ## export publishable ONIX repo from forge to host artifacts
	./export-publishable-repo.sh

export-publishable-repo-only:
	./export-publishable-repo.sh

verify-exported-repo: ## verify exported host ONIX repo artifact
	./verify-exported-repo.sh

publish-plan: ## verify no-upload ONIX repo publishing plan
	./prepare-publish-plan.sh

publish-dry-run: ## preview repo publication without upload/network
	./publish-dry-run.sh
