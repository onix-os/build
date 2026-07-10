# ONIX Phase 5 — Rust-first musl package/repository plane.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-5 5 500 501 502 503 504 505 506 507 508 509 510 511 512 513 514 515 list check package-policy package-layout payload-audit canonical-package-copies canonical-essential-builds canonical-local-repo ownership-collision-fix canonical-image-repo-consumption local-public-repo rust-essential-stones privilege-shared-surface rootasrole rootasrole-policy uutils-coreutils-wiring runtime-proof moss-runtime

help: ## show Phase 5 help
	@echo "ONIX Phase 5 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-17s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 5\033[0m    run current Phase 5 build/repo gates: 500..513\n"
	@printf "  \033[36mmake phase 500\033[0m  define Rust-first musl-only static-first package law\n"
	@printf "  \033[36mmake phase 501\033[0m  define canonical packages/ layout and metadata contract\n"
	@printf "  \033[36mmake phase 502\033[0m  provide runtime-clean stone payload audit helper\n"
	@printf "  \033[36mmake phase 503\033[0m  copy existing recipes into canonical packages/ layout\n"
	@printf "  \033[36mmake phase 504\033[0m  prove essential package builds use canonical recipes\n"
	@printf "  \033[36mmake phase 505\033[0m  assemble one canonical local ONIX package repo\n"
	@printf "  \033[36mmake phase 506\033[0m  fix/prove reboot and poweroff package ownership\n"
	@printf "  \033[36mmake phase 507\033[0m  make the image consume the canonical local repo\n"
	@printf "  \033[36mmake phase 508\033[0m  assemble local public repo layout without upload\n"
	@printf "  \033[36mmake phase 509\033[0m  build/audit first Rust essential stones\n"
	@printf "  \033[36mmake phase 510\033[0m  build/audit PAM + seccomp shared-library stones\n"
	@printf "  \033[36mmake phase 511\033[0m  build/audit RootAsRole privilege stone\n"
	@printf "  \033[36mmake phase 512\033[0m  build/audit live RootAsRole policy stone\n"
	@printf "  \033[36mmake phase 513\033[0m  wire uutils command links instead of BusyBox links\n"
	@printf "  \033[36mmake phase 514\033[0m  install, boot, and prove Phase 5 runtime ownership\n"
	@printf "  \033[36mmake phase 515\033[0m  package moss and prove in-VM repo consumption\n"

phase: ## run a Phase 5 learning alias
	@case "$(PHASE_ARG)" in \
	  5) $(MAKE) --no-print-directory phase-5 ;; \
	  500) $(MAKE) --no-print-directory package-policy ;; \
	  501) $(MAKE) --no-print-directory package-layout ;; \
	  502) $(MAKE) --no-print-directory payload-audit ;; \
	  503) $(MAKE) --no-print-directory canonical-package-copies ;; \
	  504) $(MAKE) --no-print-directory canonical-essential-builds ;; \
	  505) $(MAKE) --no-print-directory canonical-local-repo ;; \
	  506) $(MAKE) --no-print-directory ownership-collision-fix ;; \
	  507) $(MAKE) --no-print-directory canonical-image-repo-consumption ;; \
	  508) $(MAKE) --no-print-directory local-public-repo ;; \
	  509) $(MAKE) --no-print-directory rust-essential-stones ;; \
	  510) $(MAKE) --no-print-directory privilege-shared-surface ;; \
	  511) $(MAKE) --no-print-directory rootasrole ;; \
	  512) $(MAKE) --no-print-directory rootasrole-policy ;; \
	  513) $(MAKE) --no-print-directory uutils-coreutils-wiring ;; \
	  514) $(MAKE) --no-print-directory runtime-proof ;; \
	  515) $(MAKE) --no-print-directory moss-runtime ;; \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  *) echo "unknown Phase 5 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

5 500 501 502 503 504 505 506 507 508 509 510 511 512 513 514 515 list:
	@:

phase-5: ## run current Phase 5 build/repo gates in order
	@set -e; \
	for phase in 500 501 502 503 504 505 506 507 508 509 510 511 512 513; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done

check: ## host-side validation for Phase 5 docs/routing
	@test -f docs/phase_5_rust_first_musl_package_repository_plane.md
	@test -f docs/500_rust_first_musl_only_static_first_package_law.md
	@test -f docs/501_canonical_package_layout_metadata_contract.md
	@test -f docs/502_runtime_clean_stone_payload_audit_helper.md
	@test -f docs/503_copy_existing_recipes_into_canonical_package_layout.md
	@test -f docs/504_canonical_essential_package_build_lane.md
	@test -f docs/505_canonical_local_onix_package_repo.md
	@test -f docs/506_essential_package_ownership_collision_fix.md
	@test -f docs/507_canonical_repo_image_consumption.md
	@test -f docs/508_local_public_repository_layout.md
	@test -f docs/509_first_rust_essential_stones.md
	@test -f docs/510_privilege_shared_library_surface.md
	@test -f docs/511_rootasrole_privilege_stone.md
	@test -f docs/512_rootasrole_policy_stone.md
	@test -f docs/513_uutils_command_ownership.md
	@test -f docs/514_booted_phase_5_runtime_proof.md
	@test -f docs/515_moss_runtime_package_and_self_repo_probe.md
	@bash -n audit-stone-payload.sh
	@bash -n canonical-package-copies.sh
	@bash -n canonical-essential-builds.sh
	@bash -n assemble-canonical-local-repo.sh
	@bash -n fix-essential-ownership.sh
	@bash -n canonical-image-repo-consumption.sh
	@bash -n assemble-local-public-repo.sh
	@bash -n build-rust-essential-stones.sh
	@bash -n build-privilege-shared-surface.sh
	@bash -n build-rootasrole.sh
	@bash -n build-rootasrole-policy.sh
	@bash -n wire-uutils-coreutils.sh
	@bash -n phase5-runtime-proof.sh
	@bash -n build-moss-runtime.sh
	@bash -n moss-runtime-self-repo-proof.sh
	@./audit-stone-payload.sh --self-test >/dev/null
	@./canonical-package-copies.sh --check >/dev/null
	@./canonical-essential-builds.sh --check >/dev/null
	@./assemble-canonical-local-repo.sh --check >/dev/null
	@./fix-essential-ownership.sh --check >/dev/null
	@./canonical-image-repo-consumption.sh --check >/dev/null
	@./assemble-local-public-repo.sh --check >/dev/null
	@./build-rust-essential-stones.sh --check >/dev/null
	@./build-privilege-shared-surface.sh --check >/dev/null
	@./build-rootasrole.sh --check >/dev/null
	@./build-rootasrole-policy.sh --check >/dev/null
	@./wire-uutils-coreutils.sh --check >/dev/null
	@./phase5-runtime-proof.sh --check >/dev/null
	@./moss-runtime-self-repo-proof.sh --check >/dev/null
	@test -d ../../packages
	@test -d ../../packages/base
	@test -d ../../packages/core
	@test -d ../../packages/libs
	@test -d ../../packages/services
	@test -d ../../packages/templates
	@test -f ../../packages/README.md
	@test -f ../../packages/STONES.md
	@test -f ../../packages/templates/PACKAGE.md
	@test -f ../../packages/templates/stone.yaml
	@test -f ../../packages/core/uutils-coreutils/PACKAGE.md
	@test -f ../../packages/core/uutils-coreutils/stone.yaml.in
	@test -f ../../packages/core/rootasrole/PACKAGE.md
	@test -f ../../packages/core/rootasrole/stone.yaml.in
	@test -f ../../packages/core/moss/PACKAGE.md
	@test -f ../../packages/core/moss/stone.yaml.in
	@test -f ../../packages/services/rootasrole-policy/PACKAGE.md
	@test -f ../../packages/services/rootasrole-policy/stone.yaml.in
	@test -f ../../packages/libs/linux-pam/PACKAGE.md
	@test -f ../../packages/libs/linux-pam/stone.yaml.in
	@test -f ../../packages/libs/libseccomp/PACKAGE.md
	@test -f ../../packages/libs/libseccomp/stone.yaml.in
	@test -f ../../packages/libs/libgcc-runtime/PACKAGE.md
	@test -f ../../packages/libs/libgcc-runtime/stone.yaml.in
	@grep -q 'Rust-first' ../../packages/README.md
	@grep -q 'musl-only' ../../packages/README.md
	@grep -q 'runtime-clean' ../../packages/README.md
	@grep -q 'uutils-coreutils' ../../packages/STONES.md
	@grep -q 'rootasrole' ../../packages/STONES.md
	@grep -q 'moss' ../../packages/STONES.md
	@grep -q 'linux-pam' ../../packages/STONES.md
	@grep -q 'libseccomp' ../../packages/STONES.md
	@grep -q 'libgcc-runtime' ../../packages/STONES.md
	@grep -q 'rootasrole-policy' ../../packages/STONES.md
	@grep -q 'Implementation language' ../../packages/templates/PACKAGE.md
	@grep -q 'Rust alternative considered' ../../packages/templates/PACKAGE.md
	@grep -q 'Link model' ../../packages/templates/PACKAGE.md
	@grep -q 'No runtime .*nix/store.* dependency' ../../packages/templates/PACKAGE.md
	@echo "phase5   : check OK"

package-policy: ## define Rust-first musl-only static-first package law
	@echo "Phase 5 starts the ONIX package/repository plane."
	@echo
	@echo "Hard policy for ONIX system packages:"
	@echo "  - Rust-first: prefer serious Rust implementations whenever they exist."
	@echo "  - musl-only: no glibc runtime in system packages."
	@echo "  - runtime-clean: no /nix/store runtime dependency."
	@echo "  - static-first: try static/static-PIE musl first by default."
	@echo "  - minimal shared surface: allow shared libraries only when package-owned,"
	@echo "    documented, and genuinely needed."
	@echo "  - package-owned: installed system files come from stones consumed by moss."
	@echo
	@echo "Allowed during bootstrap:"
	@echo "  - Nix may provide build tools like rustc, cargo, gcc, make, or pkg-config."
	@echo
	@echo "Not allowed in finished system stones:"
	@echo "  - glibc loader paths such as /lib64/ld-linux-x86-64.so.2"
	@echo "  - RPATH/RUNPATH into /nix/store"
	@echo "  - shebangs pointing into /nix/store"
	@echo "  - systemd units calling /nix/store"
	@echo
	@echo "Next: Phase 501 will define the canonical recipe layout and package metadata."

package-layout: ## define canonical packages/ layout and metadata contract
	@echo "Phase 501 defines the canonical ONIX package workspace."
	@echo
	@echo "Canonical root:"
	@echo "  packages/"
	@echo
	@echo "Initial groups:"
	@echo "  packages/base/      ONIX identity, filesystem, defaults, policy"
	@echo "  packages/core/      core command packages; Rust-first and static-first by default"
	@echo "  packages/services/  daemons, service units, and service policy packages"
	@echo
	@echo "Required files for each package:"
	@echo "  stone.yaml"
	@echo "  PACKAGE.md"
	@echo
	@echo "Templates:"
	@echo "  packages/templates/stone.yaml"
	@echo "  packages/templates/PACKAGE.md"
	@echo
	@echo "Metadata must explain Rust choice, musl link model, the static-first attempt,"
	@echo "runtime cleanliness, runtime dependencies, and any minimal shared-library"
	@echo "exception before the package can become canonical."

payload-audit: ## provide runtime-clean stone payload audit helper
	@echo "Phase 502 provides the runtime-clean stone payload audit helper."
	@echo
	@echo "Helper:"
	@echo "  vm/phase5/audit-stone-payload.sh"
	@echo
	@echo "Default policy:"
	@echo "  - reject /nix/store references"
	@echo "  - reject glibc ELF interpreters"
	@echo "  - reject /nix/store RPATH/RUNPATH"
	@echo "  - reject dynamic NEEDED shared libraries by default"
	@echo "  - allow only documented, ONIX-owned minimal shared-library exceptions"
	@echo "  - accept static or static-pie musl payloads"
	@echo
	@echo "Self-test:"
	@./audit-stone-payload.sh --self-test
	@echo
	@echo "Use later on a prepared payload directory:"
	@echo "  vm/phase5/audit-stone-payload.sh path/to/payload"

canonical-package-copies: ## copy existing recipes into canonical packages/ layout
	./canonical-package-copies.sh --check

canonical-essential-builds: ## prove essential package builds use canonical recipes
	@if [ "$${ONIX_PHASE504_REBUILD:-0}" = "1" ]; then \
	  ./canonical-essential-builds.sh --rebuild; \
	else \
	  ./canonical-essential-builds.sh --check; \
	fi

canonical-local-repo: ## assemble one canonical local ONIX package repo
	./assemble-canonical-local-repo.sh --assemble

ownership-collision-fix: ## fix/prove reboot and poweroff package ownership
	@if [ "$${ONIX_PHASE506_REBUILD:-0}" = "1" ]; then \
	  ./fix-essential-ownership.sh --rebuild; \
	else \
	  ./fix-essential-ownership.sh --check; \
	fi

canonical-image-repo-consumption: ## make the image consume the canonical local repo
	./canonical-image-repo-consumption.sh --apply

local-public-repo: ## assemble local public repo layout without upload
	./assemble-local-public-repo.sh --assemble

rust-essential-stones: ## build/audit first Rust essential stones
	@if [ "$${ONIX_PHASE509_REBUILD:-0}" = "1" ]; then \
	  ./build-rust-essential-stones.sh --rebuild; \
	else \
	  ./build-rust-essential-stones.sh --apply; \
	fi

privilege-shared-surface: ## build/audit PAM + seccomp shared-library stones
	@if [ "$${ONIX_PHASE510_REBUILD:-0}" = "1" ]; then \
	  ./build-privilege-shared-surface.sh --rebuild; \
	else \
	  ./build-privilege-shared-surface.sh --apply; \
	fi

rootasrole: ## build/audit RootAsRole privilege stone
	@if [ "$${ONIX_PHASE511_REBUILD:-0}" = "1" ]; then \
	  ./build-rootasrole.sh --rebuild; \
	else \
	  ./build-rootasrole.sh --apply; \
	fi

rootasrole-policy: ## build/audit live RootAsRole policy stone
	@if [ "$${ONIX_PHASE512_REBUILD:-0}" = "1" ]; then \
	  ./build-rootasrole-policy.sh --rebuild; \
	else \
	  ./build-rootasrole-policy.sh --apply; \
	fi

uutils-coreutils-wiring: ## move command links from BusyBox to uutils
	@if [ "$${ONIX_PHASE513_REBUILD:-0}" = "1" ]; then \
	  ./wire-uutils-coreutils.sh --rebuild; \
	else \
	  ./wire-uutils-coreutils.sh --apply; \
	fi

runtime-proof: ## install, boot, and prove Phase 5 runtime ownership
	./phase5-runtime-proof.sh --apply

moss-runtime: ## package moss and prove in-VM repo consumption
	./moss-runtime-self-repo-proof.sh --apply
