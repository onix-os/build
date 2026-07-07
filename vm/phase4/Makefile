# ONIX Phase 4 — booted ONIX base userspace.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-4 4 400 401 402 403 404 405 406 407 408 409 410 list check cleanup readiness materialize-etc materialize-accounts serial-console network-inspection remote-inspection ssh-access ownership-audit local-stone-contract busybox-stone install-busybox-stone

help: ## show Phase 4 help
	@echo "ONIX Phase 4 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 4\033[0m    run all Phase 4 steps: 400..410\n"
	@printf "  \033[36mmake phase 400\033[0m  verify/document Phase 4 booted-base direction\n"
	@printf "  \033[36mmake phase 401\033[0m  materialize live /etc from packaged defaults\n"
	@printf "  \033[36mmake phase 402\033[0m  materialize base users/groups/shell policy\n"
	@printf "  \033[36mmake phase 403\033[0m  prove bootstrap serial root console\n"
	@printf "  \033[36mmake phase 404\033[0m  prove minimal QEMU user networking\n"
	@printf "  \033[36mmake phase 405\033[0m  prove host-to-guest TCP inspection\n"
	@printf "  \033[36mmake phase 406\033[0m  prove authenticated SSH access\n"
	@printf "  \033[36mmake phase 407\033[0m  audit temporary Nix-sourced system payloads\n"
	@printf "  \033[36mmake phase 408\033[0m  define local stone/repo contract\n"
	@printf "  \033[36mmake phase 409\033[0m  build source-based onix-busybox stone\n"
	@printf "  \033[36mmake phase 410\033[0m  install/use onix-busybox in the image\n"

phase: ## run a Phase 4 learning alias
	@case "$(PHASE_ARG)" in \
	  4) $(MAKE) --no-print-directory phase-4 ;; \
	  400) $(MAKE) --no-print-directory readiness ;; \
	  401) $(MAKE) --no-print-directory materialize-etc ;; \
	  402) $(MAKE) --no-print-directory materialize-accounts ;; \
	  403) $(MAKE) --no-print-directory serial-console ;; \
	  404) $(MAKE) --no-print-directory network-inspection ;; \
	  405) $(MAKE) --no-print-directory remote-inspection ;; \
	  406) $(MAKE) --no-print-directory ssh-access ;; \
	  407) $(MAKE) --no-print-directory ownership-audit ;; \
	  408) $(MAKE) --no-print-directory local-stone-contract ;; \
	  409) $(MAKE) --no-print-directory busybox-stone ;; \
	  410) $(MAKE) --no-print-directory install-busybox-stone ;; \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  *) echo "unknown Phase 4 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

4 400 401 402 403 404 405 406 407 408 409 410 list:
	@:

phase-4: ## run every Phase 4 step in order
	@set -e; \
	for phase in 400 401 402 403 404 405 406 407 408 409 410; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done

check: ## host-side validation for Phase 4 docs/routing
	@bash -n materialize-etc.sh
	@bash -n serial-console-probe.sh
	@bash -n network-probe.sh
	@bash -n remote-inspection-probe.sh
	@bash -n remote-inspection-host-check.sh
	@bash -n ssh-probe.sh
	@bash -n ssh-host-check.sh
	@bash -n ownership-audit.sh
	@bash -n local-stone-contract.sh
	@bash -n build-busybox-stone.sh
	@test -f stone-recipes/onix-busybox/stone.yaml.in
	@echo "phase4   : check OK"

cleanup: ## cleanup stale Phase 4 image mounts
	@./serial-console-probe.sh --kill
	@./network-probe.sh --kill
	@./remote-inspection-probe.sh --kill
	@./ssh-probe.sh --kill
	./materialize-etc.sh --cleanup-stale

readiness: ## verify/document Phase 4 booted-base direction
	@echo "Phase 4 starts from the Phase 2 boot proof."
	@echo
	@echo "Phase 4 goal:"
	@echo "  turn the booted ONIX image into a usable base system."
	@echo
	@echo "Initial work will focus on:"
	@echo "  - live /etc materialization from /usr/share/defaults"
	@echo "  - users/groups/shell policy"
	@echo "  - bootstrap serial console proof"
	@echo "  - minimal networking and remote inspection"
	@echo
	@echo "Kernel ownership remains reserved for Phase 3."

materialize-etc: ## materialize live /etc from packaged defaults in the image
	./materialize-etc.sh

materialize-accounts: ## materialize base users/groups/shell policy in the image
	./materialize-etc.sh --accounts

serial-console: ## install and prove bootstrap serial root console
	./materialize-etc.sh --serial-console
	./serial-console-probe.sh

network-inspection: ## install and prove minimal QEMU user networking
	./materialize-etc.sh --network
	./network-probe.sh

remote-inspection: ## install and prove host-to-guest TCP inspection
	./materialize-etc.sh --remote-inspection
	./remote-inspection-probe.sh

ssh-access: ## install and prove authenticated SSH access
	./materialize-etc.sh --ssh
	./ssh-probe.sh

ownership-audit: ## audit temporary Nix-sourced system payloads
	./ownership-audit.sh

local-stone-contract: ## define local Phase 4 stone/repo contract
	./local-stone-contract.sh

busybox-stone: ## build source-based onix-busybox stone
	./build-busybox-stone.sh

install-busybox-stone: ## install/use onix-busybox in the image
	./materialize-etc.sh --busybox-stone
