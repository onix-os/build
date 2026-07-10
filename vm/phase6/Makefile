# ONIX Phase 6 — nix toolbox plane.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-6 6 600 601 602 603 604 605 list check nix-architecture nix-persistent-store nix-stone nix-daemon nix-offline-proof nix-online-acceptance

help: ## show Phase 6 help
	@echo "ONIX Phase 6 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 6\033[0m    read all current Phase 6 nix planning gates: 600..605\n"
	@printf "  \033[36mmake phase 600\033[0m  plan nix architecture contract\n"
	@printf "  \033[36mmake phase 601\033[0m  plan persistent /nix store and users\n"
	@printf "  \033[36mmake phase 602\033[0m  plan nix stone package\n"
	@printf "  \033[36mmake phase 603\033[0m  plan nix daemon/config/shell integration\n"
	@printf "  \033[36mmake phase 604\033[0m  plan offline multi-user nix proof\n"
	@printf "  \033[36mmake phase 605\033[0m  plan online flakes/substituter acceptance\n"

phase: ## run a Phase 6 learning alias
	@case "$(PHASE_ARG)" in \
	  6) $(MAKE) --no-print-directory phase-6 ;; \
	  600) $(MAKE) --no-print-directory nix-architecture ;; \
	  601) $(MAKE) --no-print-directory nix-persistent-store ;; \
	  602) $(MAKE) --no-print-directory nix-stone ;; \
	  603) $(MAKE) --no-print-directory nix-daemon ;; \
	  604) $(MAKE) --no-print-directory nix-offline-proof ;; \
	  605) $(MAKE) --no-print-directory nix-online-acceptance ;; \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  *) echo "unknown Phase 6 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

6 600 601 602 603 604 605 list:
	@:

phase-6: ## read current Phase 6 nix planning gates in order
	@set -e; \
	for phase in 600 601 602 603 604 605; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done

check: ## host-side validation for Phase 6 docs/routing
	@test -f docs/phase_6_nix_toolbox_plane.md
	@test -f docs/600_nix_architecture_contract.md
	@test -f docs/601_persistent_nix_store_and_users.md
	@test -f docs/602_nix_stone_package.md
	@test -f docs/603_nix_daemon_config_shell_integration.md
	@test -f docs/604_offline_multi_user_nix_proof.md
	@test -f docs/605_online_flakes_substituter_acceptance.md
	@grep -q 'nix toolbox plane' docs/phase_6_nix_toolbox_plane.md
	@grep -q 'nix may own /nix/store' docs/phase_6_nix_toolbox_plane.md
	@grep -q 'Phase 6 is nix-only' docs/phase_6_nix_toolbox_plane.md
	@if grep -RIn '\bNix\b' docs >/tmp/onix-phase6-nix-case.$$ 2>/dev/null; then \
	  cat /tmp/onix-phase6-nix-case.$$ >&2; \
	  rm -f /tmp/onix-phase6-nix-case.$$; \
	  echo "error: Phase 6 docs should use lowercase nix" >&2; \
	  exit 1; \
	fi; \
	rm -f /tmp/onix-phase6-nix-case.$$
	@if grep -RIn 'fish shell stone\|BusyBox `sh` and fish\|default login shell runtime proof' docs >/tmp/onix-phase6-fish.$$ 2>/dev/null; then \
	  cat /tmp/onix-phase6-fish.$$ >&2; \
	  rm -f /tmp/onix-phase6-fish.$$; \
	  echo "error: fish shell docs belong to Phase 5, not Phase 6" >&2; \
	  exit 1; \
	fi; \
	rm -f /tmp/onix-phase6-fish.$$
	@echo "phase6   : check OK"

nix-architecture: ## plan nix architecture contract
	@echo "Phase 600 is a planning chapter: docs/600_nix_architecture_contract.md"
	@echo "Boundary: moss owns the machine; nix owns /nix as the toolbox."

nix-persistent-store: ## plan persistent /nix store and users
	@echo "Phase 601 is a planning chapter: docs/601_persistent_nix_store_and_users.md"
	@echo "Goal: persistent /nix plus nixbld group/build users."

nix-stone: ## plan nix stone package
	@echo "Phase 602 is a planning chapter: docs/602_nix_stone_package.md"
	@echo "Goal: nix itself arrives as ONIX-owned stones installed by moss."

nix-daemon: ## plan nix daemon/config/shell integration
	@echo "Phase 603 is a planning chapter: docs/603_nix_daemon_config_shell_integration.md"
	@echo "Goal: nix-daemon, nix.conf, sh/fish profile integration for all users."

nix-offline-proof: ## plan offline multi-user nix proof
	@echo "Phase 604 is a planning chapter: docs/604_offline_multi_user_nix_proof.md"
	@echo "Goal: prove daemon/store/user profiles without network."

nix-online-acceptance: ## plan online flakes/substituter acceptance
	@echo "Phase 605 is a planning chapter: docs/605_online_flakes_substituter_acceptance.md"
	@echo "Goal: flakes, substituters, profiles, and GC acceptance."
