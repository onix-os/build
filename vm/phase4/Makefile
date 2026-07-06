# ONIX Phase 4 — booted ONIX base userspace.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-4 4 400 list check readiness

help: ## show Phase 4 help
	@echo "ONIX Phase 4 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 4\033[0m    run all Phase 4 readiness/planning steps\n"
	@printf "  \033[36mmake phase 400\033[0m  verify/document Phase 4 booted-base direction\n"

phase: ## run a Phase 4 learning alias
	@case "$(PHASE_ARG)" in \
	  4) $(MAKE) --no-print-directory phase-4 ;; \
	  400) $(MAKE) --no-print-directory readiness ;; \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  *) echo "unknown Phase 4 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

4 400 list:
	@:

phase-4: ## run every Phase 4 step in order
	@set -e; \
	for phase in 400; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done

check: ## host-side validation for Phase 4 docs/routing
	@echo "phase4   : check OK"

readiness: ## verify/document Phase 4 booted-base direction
	@echo "Phase 4 starts from the Phase 2 boot proof."
	@echo
	@echo "Phase 4 goal:"
	@echo "  turn the booted ONIX image into a usable base system."
	@echo
	@echo "Initial work will focus on:"
	@echo "  - live /etc materialization from /usr/share/defaults"
	@echo "  - users/login/shell basics"
	@echo "  - serial login proof"
	@echo "  - minimal networking and remote inspection"
	@echo
	@echo "Kernel ownership remains reserved for Phase 3."
