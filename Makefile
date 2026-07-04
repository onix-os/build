# Onix — top-level router over per-phase Makefiles.
.DEFAULT_GOAL := help

PHASE0 := vm/phase0

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase 0 00 1 01 2 02 3 03 4 04 5 05 6 06 list \
	doctor cleanup

help: ## show top-level help and phase map
	@echo "Onix top-level Makefile."
	@echo
	@echo "Common:"
	@echo "  make doctor          common health check"
	@echo "  make cleanup         common stale host-mount cleanup"
	@echo
	@echo "Phase flow:"
	@echo "  make phases          list numbered phase steps"
	@echo "  make phase 01        run numbered phase step 01"
	@echo
	@$(MAKE) --no-print-directory -C $(PHASE0) phases

phases: ## list learning-phase aliases
	@$(MAKE) --no-print-directory -C $(PHASE0) phases

phase: ## run a learning phase alias, e.g. `make phase 01`
	@$(MAKE) --no-print-directory -C $(PHASE0) phase "$(PHASE_ARG)"

# Absorb the second goal in commands like `make phase 01`, otherwise Make would
# try to build a separate target named `01` after the `phase` target completes.
0 00 1 01 2 02 3 03 4 04 5 05 6 06 list:
	@:

doctor: ## common health check; not a phase step
	@$(MAKE) --no-print-directory -C $(PHASE0) check
	@missing=0; \
	for c in qemu-system-x86_64 losetup findmnt sgdisk partprobe mkfs.fat mkfs.ext4 mount umount chroot modprobe truncate curl sha256sum sudo ssh ssh-keygen visudo; do \
	  if ! command -v $$c >/dev/null 2>&1; then echo "missing   : $$c"; missing=1; fi; \
	done; \
	[ $$missing -eq 0 ] || exit 1; \
	echo "doctor    : host tools OK"

cleanup: ## common cleanup for stale host loop/NBD mounts
	@$(MAKE) --no-print-directory -C $(PHASE0) cleanup-stale
