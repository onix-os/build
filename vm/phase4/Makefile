# ONIX Phase 4 — booted ONIX base userspace.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-4 4 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 419 420 421 422 424 425 list check stop cleanup readiness materialize-etc materialize-accounts serial-console network-inspection remote-inspection ssh-access ownership-audit local-stone-contract busybox-stone install-busybox-stone stone-busybox-proof dropbear-stone install-dropbear-stone systemd-ownership-audit systemd-stone install-systemd-stone stone-systemd-proof bootstrap-policy-stone bootstrap-policy-proof booted-base-ownership-audit prune-stale-bootstrap-nix native-systemd-prep native-systemd-stone native-systemd-proof native-systemd-up phase4-acceptance

help: ## show Phase 4 help
	@echo "ONIX Phase 4 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 4\033[0m    run canonical Phase 4 build/proof steps: 400..422\n"
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
	@printf "  \033[36mmake phase 411\033[0m  boot-prove shell/network/SSH with onix-busybox\n"
	@printf "  \033[36mmake phase 412\033[0m  build source-based onix-dropbear stone\n"
	@printf "  \033[36mmake phase 413\033[0m  install/use onix-dropbear and prove SSH\n"
	@printf "  \033[36mmake phase 414\033[0m  audit systemd ownership before packaging\n"
	@printf "  \033[36mmake phase 415\033[0m  build bootstrap onix-systemd stone\n"
	@printf "  \033[36mmake phase 416\033[0m  install/use onix-systemd in the image\n"
	@printf "  \033[36mmake phase 417\033[0m  boot-prove onix-systemd as PID 1 runtime\n"
	@printf "  \033[36mmake phase 418\033[0m  package/prove bootstrap policy ownership\n"
	@printf "  \033[36mmake phase 419\033[0m  audit booted-base ownership/debt map\n"
	@printf "  \033[36mmake phase 420\033[0m  prune stale old Nix BusyBox/Dropbear payloads\n"
	@printf "  \033[36mmake phase 421\033[0m  prepare native source-built onix-systemd plan\n"
	@printf "  \033[36mmake phase 422\033[0m  build/install/boot-prove native onix-systemd\n"
	@printf "  \033[36mmake phase 424\033[0m  boot native ONIX, prove SSH, and leave QEMU running\n"
	@printf "  \033[36mmake phase 425\033[0m  final Phase 4 acceptance check against the running VM\n"

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
	  411) $(MAKE) --no-print-directory stone-busybox-proof ;; \
	  412) $(MAKE) --no-print-directory dropbear-stone ;; \
	  413) $(MAKE) --no-print-directory install-dropbear-stone ;; \
	  414) $(MAKE) --no-print-directory systemd-ownership-audit ;; \
	  415) $(MAKE) --no-print-directory systemd-stone ;; \
	  416) $(MAKE) --no-print-directory install-systemd-stone ;; \
	  417) $(MAKE) --no-print-directory stone-systemd-proof ;; \
	  418) $(MAKE) --no-print-directory bootstrap-policy-stone ;; \
	  419) $(MAKE) --no-print-directory booted-base-ownership-audit ;; \
	  420) $(MAKE) --no-print-directory prune-stale-bootstrap-nix ;; \
	  421) $(MAKE) --no-print-directory native-systemd-prep ;; \
	  422) $(MAKE) --no-print-directory native-systemd-stone ;; \
	  424) $(MAKE) --no-print-directory native-systemd-up ;; \
	  425) $(MAKE) --no-print-directory phase4-acceptance ;; \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  *) echo "unknown Phase 4 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

4 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 419 420 421 422 424 425 list:
	@:

phase-4: ## run canonical Phase 4 build/proof steps in order
	@set -e; \
	for phase in 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 419 420 421 422; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done

check: ## host-side validation for Phase 4 docs/routing
	@bash -n materialize-etc.sh
	@bash -n build-native-systemd-stone.sh
	@bash -n native-systemd-probe.sh
	@bash -n native-systemd-prep.sh
	@bash -n phase4-acceptance.sh
	@bash -n prune-stale-bootstrap-nix.sh
	@bash -n serial-console-probe.sh
	@bash -n network-probe.sh
	@bash -n remote-inspection-probe.sh
	@bash -n remote-inspection-host-check.sh
	@bash -n ssh-probe.sh
	@bash -n ssh-host-check.sh
	@bash -n ownership-audit.sh
	@bash -n local-stone-contract.sh
	@bash -n build-busybox-stone.sh
	@bash -n build-bootstrap-policy-stone.sh
	@bash -n booted-base-ownership-audit.sh
	@bash -n build-dropbear-stone.sh
	@bash -n build-systemd-stone.sh
	@bash -n stone-bootstrap-policy-probe.sh
	@bash -n stone-busybox-probe.sh
	@bash -n stone-dropbear-probe.sh
	@bash -n stone-systemd-probe.sh
	@bash -n systemd-ownership-audit.sh
	@test -f stone-recipes/onix-busybox/stone.yaml.in
	@test -f stone-recipes/onix-bootstrap-policy/stone.yaml.in
	@test -f stone-recipes/onix-dropbear/stone.yaml.in
	@test -f stone-recipes/onix-systemd/stone.yaml.in
	@test -f stone-recipes/onix-systemd-native/stone.yaml.in
	@echo "phase4   : check OK"

stop: ## stop Phase 4 QEMU probes and detach stale image mounts; keep generated image
	@./serial-console-probe.sh --kill
	@./network-probe.sh --kill
	@./remote-inspection-probe.sh --kill
	@./ssh-probe.sh --kill
	@./stone-busybox-probe.sh --kill
	@./stone-dropbear-probe.sh --kill
	@./stone-systemd-probe.sh --kill
	@./native-systemd-probe.sh --kill
	@./stone-bootstrap-policy-probe.sh --kill
	./materialize-etc.sh --cleanup-stale

cleanup: ## stop Phase 4 QEMU probes and detach stale image mounts; keep generated image
	@$(MAKE) --no-print-directory stop

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

stone-busybox-proof: ## boot-prove shell/network/SSH with onix-busybox
	./materialize-etc.sh --busybox-stone
	./stone-busybox-probe.sh

dropbear-stone: ## build source-based onix-dropbear stone
	./build-dropbear-stone.sh

install-dropbear-stone: ## install/use onix-dropbear and prove SSH
	./materialize-etc.sh --dropbear-stone
	./stone-dropbear-probe.sh

systemd-ownership-audit: ## audit systemd ownership before packaging
	./systemd-ownership-audit.sh

systemd-stone: ## build bootstrap onix-systemd stone
	./build-systemd-stone.sh

install-systemd-stone: ## install/use onix-systemd in the image
	./materialize-etc.sh --systemd-stone

stone-systemd-proof: ## boot-prove onix-systemd as PID 1 runtime
	./materialize-etc.sh --systemd-stone
	./stone-systemd-probe.sh

bootstrap-policy-stone: ## package/prove bootstrap policy ownership
	./build-bootstrap-policy-stone.sh
	./materialize-etc.sh --systemd-stone
	./materialize-etc.sh --bootstrap-policy-stone
	./stone-bootstrap-policy-probe.sh

bootstrap-policy-proof: ## install/boot-prove existing bootstrap policy stone
	./materialize-etc.sh --bootstrap-policy-stone
	./stone-bootstrap-policy-probe.sh

booted-base-ownership-audit: ## audit booted-base ownership/debt map
	./booted-base-ownership-audit.sh

prune-stale-bootstrap-nix: ## prune stale old Nix BusyBox/Dropbear payloads
	./prune-stale-bootstrap-nix.sh

native-systemd-prep: ## prepare native source-built onix-systemd plan
	./native-systemd-prep.sh

native-systemd-stone: ## build/install/boot-prove native onix-systemd
	./native-systemd-probe.sh --kill
	./build-native-systemd-stone.sh
	./materialize-etc.sh --native-systemd-stone
	./native-systemd-probe.sh

native-systemd-proof: ## install/boot-prove existing native onix-systemd stone
	./native-systemd-probe.sh --kill
	./materialize-etc.sh --native-systemd-stone
	./native-systemd-probe.sh

native-systemd-up: ## install/boot-prove existing native onix-systemd stone and leave VM running
	./native-systemd-probe.sh --kill
	./materialize-etc.sh --native-systemd-stone
	ONIX_NATIVE_SYSTEMD_CONTEXT="Phase 424" \
	ONIX_NATIVE_SYSTEMD_LIVE_PROOF_LABEL="Phase 424 native ONIX bring-up" \
	ONIX_NATIVE_SYSTEMD_SSH_PROOF_LABEL="Phase 424 native ONIX SSH proof" \
	ONIX_NATIVE_SYSTEMD_SUCCESS_MESSAGE="Phase 424 brought up the native ONIX VM and left it running." \
	ONIX_NATIVE_SYSTEMD_SUCCESS_DETAILS="Phase 424 brought up the native ONIX VM with source-built onix-systemd as PID 1 while bootstrap networking and authenticated SSH still work." \
	./native-systemd-probe.sh --keep-running
	@echo
	@echo "Connect from the host with:"
	@printf '  ssh -i %s -p %s onix@127.0.0.1\n' "$(abspath ../../vm/state/id_ed25519)" "$${ONIX_NATIVE_SYSTEMD_SSH_HOST_PORT:-7630}"
	@echo
	@echo "Stop it safely with:"
	@echo "  make stop"

phase4-acceptance: ## final Phase 4 acceptance check against the running VM
	./phase4-acceptance.sh
