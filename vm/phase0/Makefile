# Onix Phase 0 — forge VM and first .stone smoke tests.
.DEFAULT_GOAL := help

VM := .
BUILD_USER ?= mason
# Default to the forge build user. Preserve the internal `make ssh USER=root`
# only when USER was supplied on the make command line, not inherited from the
# host login environment.
SSH_USER ?= $(if $(filter command line,$(origin USER)),$(USER),$(BUILD_USER))
export BUILD_USER

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase 0 00 1 01 2 02 3 03 4 04 5 05 6 06 list \
	check rootfs disk inspect-disk cleanup-stale forge run direct \
	headless snapshot ssh provision stone-hello state-smoke config dry-run \
	passwordless clean clean-all

help: ## show Phase 0 help
	@echo "Onix Phase 0 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 00\033[0m  validate scripts/config\n"
	@printf "  \033[36mmake phase 01\033[0m  one-time sudoers setup for disk builds\n"
	@printf "  \033[36mmake phase 02\033[0m  fetch rootfs + build bootable forge disk\n"
	@printf "  \033[36mmake phase 03\033[0m  boot the forge VM\n"
	@printf "  \033[36mmake phase 04\033[0m  build moss + boulder inside the forge\n"
	@printf "  \033[36mmake phase 05\033[0m  build/check/install/run first tiny .stone\n"
	@printf "  \033[36mmake phase 06\033[0m  real moss install/remove/rollback state test\n"

phase: ## run a learning phase alias, e.g. `make phase 01`
	@case "$(PHASE_ARG)" in \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  0|00) $(MAKE) --no-print-directory check ;; \
	  1|01) $(MAKE) --no-print-directory passwordless ;; \
	  2|02) $(MAKE) --no-print-directory forge ;; \
	  3|03) $(MAKE) --no-print-directory run ;; \
	  4|04) $(MAKE) --no-print-directory provision ;; \
	  5|05) $(MAKE) --no-print-directory stone-hello ;; \
	  6|06) $(MAKE) --no-print-directory state-smoke ;; \
	  *) echo "unknown phase: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

# Absorb the second goal in commands like `make phase 01`, otherwise Make would
# try to build a separate target named `01` after the `phase` target completes.
0 00 1 01 2 02 3 03 4 04 5 05 6 06 list:
	@:

check: ## cheap non-mutating validation (syntax, cached rootfs, dry-run construction)
	@bash -n $(VM)/config.sh $(VM)/fetch-rootfs.sh $(VM)/build-disk.sh $(VM)/launch.sh $(VM)/ssh.sh $(VM)/install-sudoers.sh $(VM)/clean.sh $(VM)/build-hello-stone.sh $(VM)/state-smoke.sh
	@sh -n $(VM)/chroot-setup.sh $(VM)/provision.sh
	@bash -c 'source $(VM)/config.sh; \
	  if [[ -f "$$ROOTFS_PATH" ]]; then \
	    echo "$$ROOTFS_SHA256  $$ROOTFS_PATH" | sha256sum -c --status && echo "rootfs    : checksum OK"; \
	  else \
	    echo "rootfs    : not downloaded (run make phase 02)"; \
	  fi'
	@$(VM)/launch.sh --direct --dry-run >/dev/null 2>&1 || { echo "dry-run  : failed"; exit 1; }
	@echo "check     : OK"

rootfs: ## download + verify the Alpine minirootfs tarball
	$(VM)/fetch-rootfs.sh

passwordless: ## one-time: allow build-disk.sh to run without a sudo password
	$(VM)/install-sudoers.sh

disk: ## build the bootable musl forge disk (root via sudo re-exec)
	$(VM)/build-disk.sh

inspect-disk: ## read-only inspect ESP/root boot files inside the disk image
	$(VM)/build-disk.sh --inspect

cleanup-stale: ## cleanup stale loop mounts from interrupted/failed disk builds
	$(VM)/build-disk.sh --cleanup-stale

forge: rootfs disk ## fetch rootfs + build disk in one go
	@echo "forge disk ready — run 'make phase 03' from the repo root to boot it"

run: ## boot the forge (grub-efi + OVMF)
	$(VM)/launch.sh

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

dry-run: ## print the QEMU command phase 03 would execute
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
