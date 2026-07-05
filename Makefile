# ONIX — top-level router over per-phase Makefiles.
.DEFAULT_GOAL := help

PHASE0 := vm/phase0
PHASE1 := vm/phase1
PHASE2 := vm/phase2

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase 0 1 2 000 001 002 003 004 005 006 100 101 102 103 104 105 106 107 108 200 201 202 203 204 205 206 207 208 209 list \
	doctor cleanup

help: ## show top-level help and phase map
	@echo "ONIX top-level Makefile."
	@echo
	@echo "Common:"
	@echo "  make doctor          common health check"
	@echo "  make cleanup         stop forge QEMU, detach mounts, remove generated disks"
	@echo
	@echo "Phase flow:"
	@echo "  make phases          list numbered phase steps"
	@echo "  make phase 002       run one numbered phase step"
	@echo "  make phase 0         run every 0xx phase step in order"
	@echo
	@$(MAKE) --no-print-directory phases

phases: ## list learning-phase aliases
	@printf "  \033[1m--- Phase 0: forge VM + first .stone smoke tests ---\033[0m\n"
	@$(MAKE) --no-print-directory -C $(PHASE0) phases
	@printf "\n"
	@printf "  \033[1m--- Phase 1: first real ONIX stones ---\033[0m\n"
	@$(MAKE) --no-print-directory -C $(PHASE1) phases
	@printf "\n"
	@printf "  \033[1m--- Phase 2: first bootable ONIX image ---\033[0m\n"
	@$(MAKE) --no-print-directory -C $(PHASE2) phases

phase: ## run a learning phase alias, e.g. `make phase 002`
	@case "$(PHASE_ARG)" in \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  0|000|001|002|003|004|005|006) $(MAKE) --no-print-directory -C $(PHASE0) phase "$(PHASE_ARG)" ;; \
	  1|100|101|102|103|104|105|106|107|108) $(MAKE) --no-print-directory -C $(PHASE1) phase "$(PHASE_ARG)" ;; \
	  2|200|201|202|203|204|205|206|207|208|209) $(MAKE) --no-print-directory -C $(PHASE2) phase "$(PHASE_ARG)" ;; \
	  *) echo "unknown phase: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

# Absorb the second goal in commands like `make phase 002`, otherwise Make
# would try to build a separate target named `002` after `phase` completes.
0 1 2 000 001 002 003 004 005 006 100 101 102 103 104 105 106 107 108 200 201 202 203 204 205 206 207 208 209 list:
	@:

doctor: ## common health check; not a phase step
	@$(MAKE) --no-print-directory -C $(PHASE0) check
	@$(MAKE) --no-print-directory -C $(PHASE1) check
	@$(MAKE) --no-print-directory -C $(PHASE2) check
	@missing=0; \
	for c in qemu-system-x86_64 losetup findmnt sgdisk partprobe mkfs.fat mkfs.ext4 mkfs.xfs mount umount chroot modprobe truncate tar blkid bootctl curl sha256sum sudo ssh ssh-keygen visudo; do \
	  if ! command -v $$c >/dev/null 2>&1; then echo "missing   : $$c"; missing=1; fi; \
	done; \
	[ $$missing -eq 0 ] || exit 1; \
	echo "doctor    : host tools OK"
	@$(MAKE) --no-print-directory -C $(PHASE0) passwordless

cleanup: ## stop QEMU, detach mounts, remove generated disk state
	@$(MAKE) --no-print-directory -C $(PHASE0) cleanup
	@$(MAKE) --no-print-directory -C $(PHASE2) cleanup
