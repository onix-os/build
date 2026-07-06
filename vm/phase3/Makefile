# ONIX Phase 3 — reserved kernel/initramfs/modules ownership.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-3 3 300 list check kernel-deferred

help: ## show Phase 3 help
	@echo "ONIX Phase 3 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-17s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 3\033[0m    explain deferred ONIX-owned kernel work\n"
	@printf "  \033[36mmake phase 300\033[0m  document the deferred kernel/initramfs/modules contract\n"

phase: ## run a Phase 3 learning alias
	@case "$(PHASE_ARG)" in \
	  3|300) $(MAKE) --no-print-directory kernel-deferred ;; \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  *) echo "unknown Phase 3 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

3 300 list:
	@:

phase-3: ## explain why Phase 3 is reserved for later
	@$(MAKE) --no-print-directory kernel-deferred

check: ## host-side validation for Phase 3 docs/routing
	@echo "phase3   : check OK"

kernel-deferred: ## document deferred kernel ownership
	@echo "Phase 3 is intentionally reserved for ONIX-owned kernel/initramfs/modules."
	@echo
	@echo "Current state:"
	@echo "  - Phase 2 boots using the borrowed Alpine virt kernel/initramfs/module set."
	@echo "  - That is acceptable for proving image assembly and systemd-on-musl."
	@echo
	@echo "Later Phase 3 will replace the borrowed payload with ONIX-owned:"
	@echo "  - kernel build/config"
	@echo "  - initramfs generation"
	@echo "  - matching module package"
	@echo "  - boot entry/update policy"
	@echo
	@echo "For now, continue with Phase 4: booted ONIX base userspace."
