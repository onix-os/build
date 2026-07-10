# ONIX — top-level router over per-phase Makefiles.
.DEFAULT_GOAL := help

PHASE0 := vm/phase0
PHASE1 := vm/phase1
PHASE2 := vm/phase2
PHASE3 := vm/phase3
PHASE4 := vm/phase4
PHASE5 := vm/phase5
PHASE6 := vm/phase6

PHASE_ARG := $(word 2,$(MAKECMDGOALS))
ATTACHED ?= 0

.PHONY: help phases phase 0 1 2 3 4 5 6 000 001 002 003 004 005 006 100 101 102 103 104 105 106 107 108 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 300 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 419 420 421 422 424 425 500 501 502 503 504 505 506 507 508 509 510 511 512 513 514 515 516 517 518 600 601 602 603 604 605 list \
	doctor kvm stop cleanup up book book-serve

help: ## show top-level help and phase map
	@echo "ONIX top-level Makefile."
	@echo
	@echo "Common:"
	@echo "  make doctor          common health check"
	@echo "  make kvm             explain QEMU/KVM acceleration status"
	@echo "  make stop            stop QEMU/probes and detach stale mounts; keep disks/images"
	@echo "  make cleanup         destructive: stop everything and remove generated disks/images"
	@echo "  make up              boot native ONIX, prove SSH, and leave QEMU running"
	@echo "  make book            build the mdBook documentation"
	@echo "  make book-serve      serve the mdBook locally"
	@echo
	@echo "Phase flow:"
	@echo "  make phases          list numbered phase steps"
	@echo "  make phase 002       run one numbered phase step"
	@echo "  make phase 0         run every 0xx phase step in order"
	@echo "  make phase 3         explain deferred kernel ownership"
	@echo "  make phase 4         run canonical Phase 4 build/proof steps: 400..422"
	@echo "  make phase 424       boot native ONIX and leave it running for inspection"
	@echo "  make phase 425       final Phase 4 acceptance check against that running VM"
	@echo "  make phase 5         run current Phase 5 package/repository gates"
	@echo "  make phase 514       install, boot, and prove Phase 5 runtime ownership"
	@echo "  make phase 515       package moss and prove in-VM repo consumption"
	@echo "  make phase 516       define BusyBox sh + fish shell policy"
	@echo "  make phase 517       build/audit the fish shell stone"
	@echo "  make phase 518       install fish and prove BusyBox sh + fish login"
	@echo "  make phase 6         read current Phase 6 nix-only guide gates"
	@echo "  make phase 600       read the nix architecture contract plan"
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
	@printf "\n"
	@printf "  \033[1m--- Phase 5: Rust-first musl package/repository plane ---\033[0m\n"
	@$(MAKE) --no-print-directory -C $(PHASE5) phases
	@printf "\n"
	@printf "  \033[1m--- Phase 6: nix toolbox plane ---\033[0m\n"
	@$(MAKE) --no-print-directory -C $(PHASE6) phases

phase: ## run a learning phase alias, e.g. `make phase 002`
	@case "$(PHASE_ARG)" in \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  0|000|001|002|003|004|005|006) $(MAKE) --no-print-directory -C $(PHASE0) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  1|100|101|102|103|104|105|106|107|108) $(MAKE) --no-print-directory -C $(PHASE1) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  2|200|201|202|203|204|205|206|207|208|209|210|211|212|213|214) $(MAKE) --no-print-directory -C $(PHASE2) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  3|300) $(MAKE) --no-print-directory -C $(PHASE3) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  4|400|401|402|403|404|405|406|407|408|409|410|411|412|413|414|415|416|417|418|419|420|421|422|424|425) $(MAKE) --no-print-directory -C $(PHASE4) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  5|500|501|502|503|504|505|506|507|508|509|510|511|512|513|514|515|516|517|518) $(MAKE) --no-print-directory -C $(PHASE5) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  6|600|601|602|603|604|605) $(MAKE) --no-print-directory -C $(PHASE6) phase "$(PHASE_ARG)" ATTACHED="$(ATTACHED)" ;; \
	  *) echo "unknown phase: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

# Absorb the second goal in commands like `make phase 002`, otherwise Make
# would try to build a separate target named `002` after `phase` completes.
0 1 2 3 4 5 6 000 001 002 003 004 005 006 100 101 102 103 104 105 106 107 108 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 300 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 419 420 421 422 424 425 500 501 502 503 504 505 506 507 508 509 510 511 512 513 514 515 516 517 518 600 601 602 603 604 605 list:
	@:

doctor: ## common health check; not a phase step
	@$(MAKE) --no-print-directory -C $(PHASE0) check
	@$(MAKE) --no-print-directory -C $(PHASE1) check
	@$(MAKE) --no-print-directory -C $(PHASE2) check
	@$(MAKE) --no-print-directory -C $(PHASE3) check
	@$(MAKE) --no-print-directory -C $(PHASE4) check
	@$(MAKE) --no-print-directory -C $(PHASE5) check
	@$(MAKE) --no-print-directory -C $(PHASE6) check
	@missing=0; \
	for c in qemu-system-x86_64 losetup findmnt sgdisk partprobe mkfs.fat mkfs.ext4 mkfs.xfs mount umount chroot modprobe depmod truncate tar blkid bootctl cpio curl gzip sha256sum sudo ssh ssh-keygen visudo mdbook systemd-sysusers nix readelf file nc; do \
	  if ! command -v $$c >/dev/null 2>&1; then echo "missing   : $$c"; missing=1; fi; \
	done; \
	[ $$missing -eq 0 ] || exit 1; \
	echo "doctor    : host tools OK"
	@$(MAKE) --no-print-directory -C $(PHASE0) passwordless

kvm: ## explain QEMU/KVM acceleration status
	@./vm/kvm-doctor.sh

stop: ## stop QEMU/probes and detach stale mounts; keep generated disks/images
	@$(MAKE) --no-print-directory -C $(PHASE0) stop
	@$(MAKE) --no-print-directory -C $(PHASE2) stop
	@$(MAKE) --no-print-directory -C $(PHASE4) stop

cleanup: ## destructive: stop QEMU/probes, detach mounts, remove generated disks/images
	@$(MAKE) --no-print-directory -C $(PHASE0) cleanup
	@$(MAKE) --no-print-directory -C $(PHASE2) cleanup
	@$(MAKE) --no-print-directory -C $(PHASE4) cleanup

up: ## boot native ONIX, prove SSH, and leave QEMU running
	@$(MAKE) --no-print-directory -C $(PHASE4) native-systemd-up

book: ## build the mdBook documentation
	@set -e; \
	hidden="$${ONIX_MDBOOK_HIDE_DIR:-../.onix-mdbook-hidden.$$$$}"; \
	if ! mkdir -p "$$hidden" 2>/dev/null; then \
	  echo "error: cannot create mdBook hide dir: $$hidden" >&2; \
	  echo "       set ONIX_MDBOOK_HIDE_DIR to a writable directory on the same filesystem as the repo" >&2; \
	  exit 1; \
	fi; \
	hidden_abs=$$(cd "$$hidden" && pwd -P); \
	repo_abs=$$(pwd -P); \
	case "$$hidden_abs/" in "$$repo_abs"/*) \
	  echo "error: ONIX_MDBOOK_HIDE_DIR must be outside the repository" >&2; \
	  echo "       mdBook src='.' would scan hidden artifacts if it lived under the repo" >&2; \
	  rm -rf "$$hidden"; \
	  exit 1 ;; \
	esac; \
	repo_dev=$$(stat -c '%d' .); \
	hidden_dev=$$(stat -c '%d' "$$hidden"); \
	if [ "$$repo_dev" != "$$hidden_dev" ]; then \
	  echo "error: ONIX_MDBOOK_HIDE_DIR must be on the same filesystem as the repo" >&2; \
	  echo "       cross-filesystem mv can copy root-owned image artifacts and fail halfway" >&2; \
	  rm -rf "$$hidden"; \
	  exit 1; \
	fi; \
	restore() { \
	  status=$$?; \
	  if [ -e "$$hidden/artifacts" ] || [ -L "$$hidden/artifacts" ]; then rm -rf artifacts; mv "$$hidden/artifacts" artifacts; fi; \
	  if [ -e "$$hidden/vm/state" ] || [ -L "$$hidden/vm/state" ]; then mkdir -p vm; rm -rf vm/state; mv "$$hidden/vm/state" vm/state; fi; \
	  if [ -e "$$hidden/vm/downloads" ] || [ -L "$$hidden/vm/downloads" ]; then mkdir -p vm; rm -rf vm/downloads; mv "$$hidden/vm/downloads" vm/downloads; fi; \
	  rm -rf "$$hidden"; \
	  exit $$status; \
	}; \
	trap restore EXIT INT TERM; \
	if [ -e artifacts ] || [ -L artifacts ]; then mv artifacts "$$hidden/artifacts"; fi; \
	if [ -e vm/state ] || [ -L vm/state ]; then mkdir -p "$$hidden/vm"; mv vm/state "$$hidden/vm/state"; fi; \
	if [ -e vm/downloads ] || [ -L vm/downloads ]; then mkdir -p "$$hidden/vm"; mv vm/downloads "$$hidden/vm/downloads"; fi; \
	mdbook build

book-serve: ## serve the mdBook documentation locally
	@mdbook serve -n 127.0.0.1
