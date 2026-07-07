# ONIX — top-level router over per-phase Makefiles.
.DEFAULT_GOAL := help

PHASE0 := vm/phase0
PHASE1 := vm/phase1
PHASE2 := vm/phase2
PHASE3 := vm/phase3
PHASE4 := vm/phase4

PHASE_ARG := $(word 2,$(MAKECMDGOALS))
ATTACHED ?= 0

.PHONY: help phases phase 0 1 2 3 4 000 001 002 003 004 005 006 100 101 102 103 104 105 106 107 108 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 300 400 401 402 403 404 405 406 407 408 409 410 list \
	doctor cleanup book book-serve

help: ## show top-level help and phase map
	@echo "ONIX top-level Makefile."
	@echo
	@echo "Common:"
	@echo "  make doctor          common health check"
	@echo "  make cleanup         stop forge QEMU, detach mounts, remove generated disks"
	@echo "  make book            build the mdBook documentation"
	@echo "  make book-serve      serve the mdBook locally"
	@echo
	@echo "Phase flow:"
	@echo "  make phases          list numbered phase steps"
	@echo "  make phase 002       run one numbered phase step"
	@echo "  make phase 0         run every 0xx phase step in order"
	@echo "  make phase 3         explain deferred kernel ownership"
	@echo "  make phase 4         run every 4xx phase step in order"
	@echo "  ATTACHED=1 make phase 212   run visual/interactive when a phase supports it"
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
	@printf "\n"
	@printf "  \033[1m--- Phase 3: reserved ONIX-owned kernel work ---\033[0m\n"
	@$(MAKE) --no-print-directory -C $(PHASE3) phases
	@printf "\n"
	@printf "  \033[1m--- Phase 4: booted ONIX base userspace ---\033[0m\n"
	@$(MAKE) --no-print-directory -C $(PHASE4) phases

phase: ## run a learning phase alias, e.g. `make phase 002`
	@case "$(PHASE_ARG)" in \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  0|000|001|002|003|004|005|006) $(MAKE) --no-print-directory -C $(PHASE0) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  1|100|101|102|103|104|105|106|107|108) $(MAKE) --no-print-directory -C $(PHASE1) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  2|200|201|202|203|204|205|206|207|208|209|210|211|212|213|214) $(MAKE) --no-print-directory -C $(PHASE2) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  3|300) $(MAKE) --no-print-directory -C $(PHASE3) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  4|400|401|402|403|404|405|406|407|408|409|410) $(MAKE) --no-print-directory -C $(PHASE4) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  *) echo "unknown phase: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

# Absorb the second goal in commands like `make phase 002`, otherwise Make
# would try to build a separate target named `002` after `phase` completes.
0 1 2 3 4 000 001 002 003 004 005 006 100 101 102 103 104 105 106 107 108 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 300 400 401 402 403 404 405 406 407 408 409 410 list:
	@:

doctor: ## common health check; not a phase step
	@$(MAKE) --no-print-directory -C $(PHASE0) check
	@$(MAKE) --no-print-directory -C $(PHASE1) check
	@$(MAKE) --no-print-directory -C $(PHASE2) check
	@$(MAKE) --no-print-directory -C $(PHASE3) check
	@$(MAKE) --no-print-directory -C $(PHASE4) check
	@missing=0; \
	for c in qemu-system-x86_64 losetup findmnt sgdisk partprobe mkfs.fat mkfs.ext4 mkfs.xfs mount umount chroot modprobe depmod truncate tar blkid bootctl cpio curl gzip sha256sum sudo ssh ssh-keygen visudo mdbook systemd-sysusers nix readelf file nc; do \
	  if ! command -v $$c >/dev/null 2>&1; then echo "missing   : $$c"; missing=1; fi; \
	done; \
	[ $$missing -eq 0 ] || exit 1; \
	echo "doctor    : host tools OK"
	@$(MAKE) --no-print-directory -C $(PHASE0) passwordless

cleanup: ## stop QEMU, detach mounts, remove generated disk state
	@$(MAKE) --no-print-directory -C $(PHASE0) cleanup
	@$(MAKE) --no-print-directory -C $(PHASE2) cleanup
	@$(MAKE) --no-print-directory -C $(PHASE4) cleanup

book: ## build the mdBook documentation
	@mdbook build book

book-serve: ## serve the mdBook documentation locally
	@mdbook serve book -n 127.0.0.1
