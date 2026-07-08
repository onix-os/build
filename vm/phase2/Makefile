# ONIX Phase 2 — first bootable ONIX image.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))
ATTACHED ?= 0

.PHONY: help phases phase phase-2 2 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 list check stop cleanup ready root-tree host-moss host-root-tree image-contract image-skeleton boot-skeleton kernel-plan systemd-plan systemd-musl init-decision kernel-payload boot-probe systemd-payload module-payload

help: ## show Phase 2 help
	@echo "ONIX Phase 2 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 2\033[0m    run canonical host-native Phase 2 path: 200,202..211,213,214,212\n"
	@printf "  \033[36mmake phase 200\033[0m  verify Phase 2 image-assembly readiness\n"
	@printf "  \033[36mmake phase 201\033[0m  assemble first ONIX root tree from exported repo\n"
	@printf "  \033[36mmake phase 202\033[0m  build host-side moss from pinned os-tools\n"
	@printf "  \033[36mmake phase 203\033[0m  assemble ONIX root tree with host-side moss only\n"
	@printf "  \033[36mmake phase 204\033[0m  verify the ONIX image/disk assembly contract\n"
	@printf "  \033[36mmake phase 205\033[0m  create first non-booting ONIX disk/root skeleton\n"
	@printf "  \033[36mmake phase 206\033[0m  install systemd-boot/BLS skeleton into the image\n"
	@printf "  \033[36mmake phase 207\033[0m  verify kernel + initramfs contract\n"
	@printf "  \033[36mmake phase 208\033[0m  verify systemd userspace contract\n"
	@printf "  \033[36mmake phase 209\033[0m  check systemd-on-musl feasibility\n"
	@printf "  \033[36mmake phase 210\033[0m  verify init path decision contract\n"
	@printf "  \033[36mmake phase 211\033[0m  install first kernel + initramfs payload\n"
	@printf "  \033[36mmake phase 212\033[0m  run first QEMU boot probe (ATTACHED=1 to watch)\n"
	@printf "  \033[36mmake phase 213\033[0m  stage first musl systemd userspace payload\n"
	@printf "  \033[36mmake phase 214\033[0m  stage first kernel module/kmod payload\n"

phase: ## run a Phase 2 learning alias
	@case "$(PHASE_ARG)" in \
	  2) $(MAKE) --no-print-directory phase-2 ;; \
	  200) $(MAKE) --no-print-directory ready ;; \
	  201) $(MAKE) --no-print-directory root-tree ;; \
	  202) $(MAKE) --no-print-directory host-moss ;; \
	  203) $(MAKE) --no-print-directory host-root-tree ;; \
	  204) $(MAKE) --no-print-directory image-contract ;; \
	  205) $(MAKE) --no-print-directory image-skeleton ;; \
	  206) $(MAKE) --no-print-directory boot-skeleton ;; \
	  207) $(MAKE) --no-print-directory kernel-plan ;; \
	  208) $(MAKE) --no-print-directory systemd-plan ;; \
	  209) $(MAKE) --no-print-directory systemd-musl ;; \
	  210) $(MAKE) --no-print-directory init-decision ;; \
	  211) $(MAKE) --no-print-directory kernel-payload ;; \
	  212) $(MAKE) --no-print-directory boot-probe ;; \
	  213) $(MAKE) --no-print-directory systemd-payload ;; \
	  214) $(MAKE) --no-print-directory module-payload ;; \
	  *) echo "unknown Phase 2 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

2 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 list:
	@:

phase-2: ## run every Phase 2 step in order
	@set -e; \
	for phase in 200 202 203 204 205 206 207 208 209 210 211 213 214 212; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase ATTACHED="$(ATTACHED)"; \
	done

check: ## host-side syntax validation only
	@bash -n check-readiness.sh build-root-tree.sh build-host-moss.sh build-root-tree-host.sh verify-image-contract.sh build-image-skeleton.sh verify-kernel-initramfs-plan.sh verify-systemd-userspace-plan.sh check-systemd-musl.sh verify-init-decision.sh boot-probe.sh
	@echo "phase2   : check OK"

stop: ## stop Phase 2 QEMU probe and detach stale image mounts; keep generated image
	./boot-probe.sh --kill
	./build-image-skeleton.sh --cleanup-stale

cleanup: ## destructive: stop Phase 2 probe, detach mounts, remove generated image
	./boot-probe.sh --kill
	./build-image-skeleton.sh --clean

ready: ## verify Phase 2 image-assembly readiness
	./check-readiness.sh

root-tree: ## assemble first ONIX root tree from exported repo
	./build-root-tree.sh

host-moss: ## build host-side moss from pinned os-tools
	./build-host-moss.sh

host-root-tree: ## assemble ONIX root tree with host-side moss only
	./build-root-tree-host.sh

image-contract: ## verify the ONIX image/disk assembly contract
	./verify-image-contract.sh

image-skeleton: ## create first non-booting ONIX disk/root skeleton
	./build-image-skeleton.sh

boot-skeleton: ## install systemd-boot/BLS skeleton into the image
	./build-image-skeleton.sh --boot-skeleton

kernel-plan: ## verify kernel + initramfs contract
	./verify-kernel-initramfs-plan.sh

systemd-plan: ## verify systemd userspace contract
	./verify-systemd-userspace-plan.sh

systemd-musl: ## check systemd-on-musl feasibility
	./check-systemd-musl.sh

init-decision: ## verify init path decision contract
	./verify-init-decision.sh

kernel-payload: ## install first kernel + initramfs payload
	./build-image-skeleton.sh --kernel-payload

boot-probe: ## run first QEMU boot probe
	ATTACHED="$(ATTACHED)" ./boot-probe.sh

systemd-payload: ## stage first musl systemd userspace payload
	./build-image-skeleton.sh --systemd-payload

module-payload: ## stage first kernel module/kmod payload
	./build-image-skeleton.sh --module-payload
