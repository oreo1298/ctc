# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Developer entry points. `make help` lists them. Every target is a thin
# wrapper around a script in scripts/ so CI and humans run the same thing.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

GODOT_SH := scripts/godot.sh
VENV := .venv
PY := $(VENV)/bin/python
GAME := game
# Extra arguments for `make run`, e.g. make run ARGS="--level greenmantle-01"
ARGS ?=

SHELL_SCRIPTS := $(shell find scripts tests/scripts packaging -name '*.sh' -type f 2>/dev/null | sort)
GD_SOURCES = $(shell find $(GAME) -name '*.gd' -not -path '$(GAME)/addons/*' -not -path '$(GAME)/.godot/*' | sort)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ----------------------------------------------------------------- setup ---
.PHONY: dev
dev: ## Install deps, pinned Godot + templates, linters, GUT (re-runnable)
	scripts/bootstrap.sh

.PHONY: import
import: ## (Re)import game assets headlessly
	$(GODOT_SH) --headless --path $(GAME) --import

# ------------------------------------------------------------------- run ---
.PHONY: run
run: import ## Run the game
	$(GODOT_SH) --path $(GAME) $(ARGS)

.PHONY: editor
editor: ## Open the Godot editor on the project
	$(GODOT_SH) --path $(GAME) --editor

# ------------------------------------------------------------------ test ---
.PHONY: test
test: import test-scripts test-unit smoke ## Run all tests

.PHONY: test-unit
test-unit: ## GDScript unit tests (GUT, headless)
	$(GODOT_SH) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd \
		-gdir=res://tests/unit -ginclude_subdirs -gexit -glog=1

.PHONY: test-scripts
test-scripts: ## Tests for the shell scripts
	tests/scripts/test_bootstrap_detect.sh

.PHONY: smoke
smoke: ## Boot the game headlessly for a few frames
	$(GODOT_SH) --headless --path $(GAME) -- --smoke-test

# ------------------------------------------------------------------ lint ---
.PHONY: lint
lint: lint-shell lint-gd lint-data lint-reuse lint-identity ## Run every linter

.PHONY: lint-shell
lint-shell: ## shellcheck all bash scripts
	$(VENV)/bin/shellcheck $(SHELL_SCRIPTS)

.PHONY: lint-gd
lint-gd: ## gdlint + gdformat --check
	@if [ -n "$(GD_SOURCES)" ]; then \
		$(VENV)/bin/gdlint $(GD_SOURCES) && \
		$(VENV)/bin/gdformat --check $(GD_SOURCES); \
	fi

.PHONY: lint-data
lint-data: ## Validate game data against JSON schemas
	$(PY) -I tools/validate_data.py $(GAME)/data

.PHONY: lint-reuse
lint-reuse: ## REUSE licensing compliance
	$(VENV)/bin/reuse lint

.PHONY: lint-identity
lint-identity: ## Check name/ID/version agree with app.env
	scripts/sync-identity.sh --check

.PHONY: fmt
fmt: ## Auto-format GDScript
	$(VENV)/bin/gdformat $(GD_SOURCES)

.PHONY: sync-identity
sync-identity: ## Propagate app.env into project files
	scripts/sync-identity.sh

# ------------------------------------------- build, package, install ---
# These dispatch to scripts/<target>.sh; targets whose script does not exist
# yet say which milestone adds them (docs/ROADMAP.md).
define dispatch
	@if [ -x scripts/$(1).sh ]; then scripts/$(1).sh $(ARGS); \
	else echo "make $(1): not implemented yet (see docs/ROADMAP.md)" >&2; exit 2; fi
endef

.PHONY: build
build: ## Headless exports: Linux x86_64/arm64, Windows (scripts/build.sh)
	$(call dispatch,build)

.PHONY: package
package: ## AppImage, Flatpak, deb, rpm, PKGBUILDs, Nix (scripts/package.sh)
	$(call dispatch,package)

.PHONY: install
install: ## Install for this user under ~/.local (ARGS=--system for /usr/local)
	$(call dispatch,install)

.PHONY: uninstall
uninstall: ## Remove what install added (ARGS=--purge also removes saves)
	$(call dispatch,uninstall)

.PHONY: screenshots
screenshots: ## Render key scenes to PNG (Xvfb + llvmpipe + Compatibility)
	$(call dispatch,screenshots)

.PHONY: validate-levels
validate-levels: ## Prove every campaign level is beatable; refresh par
	$(call dispatch,validate-levels)

# ----------------------------------------------------------------- clean ---
.PHONY: clean
clean: ## Remove build outputs (keeps caches and saves)
	rm -rf build dist
