# ONIX Phase 2 — first bootable ONIX image.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-2 2 200 list check ready

help: ## show Phase 2 help
	@echo "ONIX Phase 2 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 2\033[0m    run all Phase 2 steps: 200\n"
	@printf "  \033[36mmake phase 200\033[0m  verify Phase 2 image-assembly readiness\n"

phase: ## run a Phase 2 learning alias
	@case "$(PHASE_ARG)" in \
	  2) $(MAKE) --no-print-directory phase-2 ;; \
	  200) $(MAKE) --no-print-directory ready ;; \
	  *) echo "unknown Phase 2 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

2 200 list:
	@:

phase-2: ## run every Phase 2 step in order
	@$(MAKE) --no-print-directory phase 200

check: ## host-side syntax validation only
	@bash -n check-readiness.sh
	@echo "phase2   : check OK"

ready: ## verify Phase 2 image-assembly readiness
	./check-readiness.sh
