# ONIX Phase 5 — Rust-first musl package/repository plane.
.DEFAULT_GOAL := help

PHASE_ARG := $(word 2,$(MAKECMDGOALS))

.PHONY: help phases phase phase-5 5 500 501 list check package-policy package-layout

help: ## show Phase 5 help
	@echo "ONIX Phase 5 targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk -F':.*?## ' '{printf "  \033[36m%-17s\033[0m %s\n", $$1, $$2}'

phases: ## list the learning-phase aliases
	@printf "  \033[36mmake phase 5\033[0m    run current Phase 5 gates: 500..501\n"
	@printf "  \033[36mmake phase 500\033[0m  define Rust-first musl-only package/repository law\n"
	@printf "  \033[36mmake phase 501\033[0m  define canonical packages/ layout and metadata contract\n"

phase: ## run a Phase 5 learning alias
	@case "$(PHASE_ARG)" in \
	  5) $(MAKE) --no-print-directory phase-5 ;; \
	  500) $(MAKE) --no-print-directory package-policy ;; \
	  501) $(MAKE) --no-print-directory package-layout ;; \
	  ""|list) $(MAKE) --no-print-directory phases ;; \
	  *) echo "unknown Phase 5 step: $(PHASE_ARG)" >&2; $(MAKE) --no-print-directory phases; exit 2 ;; \
	esac

5 500 501 list:
	@:

phase-5: ## run current Phase 5 gates in order
	@set -e; \
	for phase in 500 501; do \
	  echo; \
	  echo "==> make phase $$phase"; \
	  $(MAKE) --no-print-directory phase $$phase; \
	done

check: ## host-side validation for Phase 5 docs/routing
	@test -f ../../book/src/phases/phase-5.md
	@test -f ../../book/src/phases/500.md
	@test -f ../../book/src/phases/501.md
	@test -d ../../packages
	@test -d ../../packages/base
	@test -d ../../packages/core
	@test -d ../../packages/services
	@test -d ../../packages/templates
	@test -f ../../packages/README.md
	@test -f ../../packages/templates/PACKAGE.md
	@test -f ../../packages/templates/stone.yaml
	@grep -q 'Rust-first' ../../packages/README.md
	@grep -q 'musl-only' ../../packages/README.md
	@grep -q 'runtime-clean' ../../packages/README.md
	@grep -q 'Implementation language' ../../packages/templates/PACKAGE.md
	@grep -q 'Rust alternative considered' ../../packages/templates/PACKAGE.md
	@grep -q 'Link model' ../../packages/templates/PACKAGE.md
	@grep -q 'No runtime .*nix/store.* dependency' ../../packages/templates/PACKAGE.md
	@echo "phase5   : check OK"

package-policy: ## define Rust-first musl-only package/repository law
	@echo "Phase 5 starts the ONIX package/repository plane."
	@echo
	@echo "Hard policy for ONIX system packages:"
	@echo "  - Rust-first: prefer serious Rust implementations whenever they exist."
	@echo "  - musl-only: no glibc runtime in system packages."
	@echo "  - runtime-clean: no /nix/store runtime dependency."
	@echo "  - self-contained: prefer static or fully self-contained musl output."
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
	@echo "  packages/core/      core command packages; Rust-first and musl-static by default"
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
	@echo "Metadata must explain Rust choice, musl/static link model, runtime cleanliness,"
	@echo "runtime dependencies, and any exception before the package can become canonical."
