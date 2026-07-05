# ONIX Phase 0 — forge VM and first .stone smoke tests.
.DEFAULT_GOAL := help

VM := .
BUILD_USER ?= mason
# Default to the forge build user. Preserve the internal `make ssh USER=root`
# only when USER was supplied on the make command line, not inherited from the
# host login environment.
SSH_USER ?= $(if $(filter command line,$(origin USER)),$(USER),$(BUILD_USER))
export BUILD_USER

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-0 0 000 001 002 003 004 005 006 list \
	check rootfs disk inspect-disk kill-qemu cleanup cleanup-stale forge run direct \
	run-wait headless snapshot ssh provision stone-hello state-smoke state-smoke-only config dry-run \
	passwordless clean clean-all

help: ## show Phase 0 help
	@echo "ONIX Phase 0 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 0\033[0m    run all Phase 0 steps: 000..006\n"
	@printf "  \033[36mmake phase 000\033[0m  validate scripts/config\n"
	@printf "  \033[36mmake phase 001\033[0m  ensure sudoers setup for disk builds\n"
	@printf "  \033[36mmake phase 002\033[0m  fetch rootfs + build bootable forge disk\n"
	@printf "  \033[36mmake phase 003\033[0m  boot the forge VM\n"
	@printf "  \033[36mmake phase 004\033[0m  build moss + boulder inside the forge\n"
	@printf "  \033[36mmake phase 005\033[0m  build/check/install/run first tiny .stone\n"
	@printf "  \033[36mmake phase 006\033[0m  real moss install/remove/rollback state test\n"

phase: ## run a learning phase alias, e.g. `make phase 002`
	@case "$(PHASE_ARG)" in \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  0) $(MAKE) --no-print-directory phase-0 ;; \
	  000) $(MAKE) --no-print-directory check ;; \
	  001) $(MAKE) --no-print-directory passwordless ;; \
	  002) $(MAKE) --no-print-directory forge ;; \
	  003) $(MAKE) --no-print-directory run ;; \
	  004) $(MAKE) --no-print-directory provision ;; \
	  005) $(MAKE) --no-print-directory stone-hello ;; \
	  006) $(MAKE) --no-print-directory state-smoke ;; \
	  *) echo "unknown phase: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

# Absorb the second goal in commands like `make phase 002`, otherwise Make
# would try to build a separate target named `002` after `phase` completes.
0 000 001 002 003 004 005 006 list:
	@:

phase-0: ## run every Phase 0 step in order
	@set -e; \
	for phase in 000 001 002; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done; \
	echo; \
	echo "==> make phase 003"; \
	$(MAKE) --no-print-directory run-wait; \
	for phase in 004 005; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done; \
	echo; \
	echo "==> make phase 006"; \
	$(MAKE) --no-print-directory state-smoke-only

check: ## cheap non-mutating validation (syntax, cached rootfs, dry-run construction)
	@bash -n $(VM)/config.sh $(VM)/fetch-rootfs.sh $(VM)/build-disk.sh $(VM)/launch.sh $(VM)/ssh.sh $(VM)/install-sudoers.sh $(VM)/clean.sh $(VM)/kill-qemu.sh $(VM)/build-hello-stone.sh $(VM)/state-smoke.sh
	@sh -n $(VM)/chroot-setup.sh $(VM)/provision.sh
	@bash -c 'source $(VM)/config.sh; \
	  if [[ -f "$$ROOTFS_PATH" ]]; then \
	    echo "$$ROOTFS_SHA256  $$ROOTFS_PATH" | sha256sum -c --status && echo "rootfs    : checksum OK"; \
	  else \
	    echo "rootfs    : not downloaded (run make phase 002)"; \
	  fi'
	@$(VM)/launch.sh --direct --dry-run >/dev/null 2>&1 || { echo "dry-run  : failed"; exit 1; }
	@echo "check     : OK"

rootfs: ## download + verify the Alpine minirootfs tarball
	$(VM)/fetch-rootfs.sh

passwordless: ## ensure build-disk.sh can run without a sudo password
	$(VM)/install-sudoers.sh --ensure

disk: ## build the bootable musl forge disk (root via sudo re-exec)
	$(VM)/build-disk.sh

inspect-disk: ## read-only inspect ESP/root boot files inside the disk image
	$(VM)/build-disk.sh --inspect

cleanup-stale: ## cleanup stale loop mounts from interrupted/failed disk builds
	$(VM)/build-disk.sh --cleanup-stale

kill-qemu:
	$(VM)/kill-qemu.sh

cleanup:
	@$(MAKE) --no-print-directory kill-qemu
	@$(MAKE) --no-print-directory cleanup-stale
	@$(MAKE) --no-print-directory clean

forge: rootfs disk ## fetch rootfs + build disk in one go
	@echo "forge disk ready — run 'make phase 003' from the repo root to boot it"

run: ## boot the forge (grub-efi + OVMF, VNC by default)
	$(VM)/launch.sh

run-wait: ## boot the forge in background, show serial log, continue when SSH is ready
	$(VM)/launch.sh --background --wait --display vnc

direct: ## boot via QEMU direct-kernel (grub bypass / safety net)
	$(VM)/launch.sh --direct

headless: ## boot the forge with VNC + serial, no window
	$(VM)/launch.sh --display vnc

snapshot: ## boot throwaway (disk writes discarded on exit)
	$(VM)/launch.sh --snapshot

ssh: ## ssh into the running forge (internal: make -C vm/phase0 ssh SSH_USER=root)
	$(VM)/ssh.sh $(SSH_USER)

provision: ## build moss + boulder inside the running forge (over ssh)
	$(VM)/ssh.sh $(BUILD_USER) ./provision.sh

stone-hello: ## build + verify a tiny hello-world .stone inside the running forge
	$(VM)/build-hello-stone.sh

state-smoke: stone-hello ## verify real moss state install/remove/rollback in a disposable root
	$(VM)/state-smoke.sh

state-smoke-only:
	$(VM)/state-smoke.sh

dry-run: ## print the QEMU command phase 003 would execute
	$(VM)/launch.sh --dry-run

config: ## print the resolved configuration
	@bash -c 'source $(VM)/config.sh; \
	  echo "forge      : $$VM_NAME ($$VM_CPUS vCPU, $$VM_RAM RAM, $$DISK_SIZE disk, user $$BUILD_USER)"; \
	  echo "seed       : $$ROOTFS_NAME (musl)"; \
	  echo "os-tools   : $$OS_TOOLS_REF"; \
	  echo "disk       : $$DISK_IMG ($$DISK_FORMAT)"; \
	  echo "ssh        : ssh -p $$SSH_PORT $$BUILD_USER@127.0.0.1"'

clean: ## remove disk + NVRAM + kernel (keeps ssh key + tarball)
	$(VM)/clean.sh

clean-all: ## remove everything incl. ssh key + tarball
	$(VM)/clean.sh --all
