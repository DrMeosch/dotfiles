# Single entry point for applying this setup. See `make help`.
#
# Everything real happens in bootstrap.sh and rebuild.sh; this file only decides
# which one to run and keeps Nix reachable while doing so.
#
#   make                  first run on a machine: bootstrap.sh
#                         every later run:        rebuild.sh
#   make update           git pull --ff-only, then make apply
#   make check            evaluate all homeConfigurations, apply nothing
#
# Variables:
#   TARGET=<name>   arch, ubuntu, wsl-arch or wsl-ubuntu (default: detected)
#   YES=1           don't prompt before rewriting the user line in flake.nix

ROOT := $(shell cd "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))" && pwd -P)
DETECT := $(ROOT)/scripts/detect-target.sh
NIX_DAEMON_SH := /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# A fresh Nix install (or a non-login shell) leaves nix off PATH. Put it there
# for the recipe's own shell, so one `make` works right after installing Nix and
# in a shell that was opened before.
NIX_ENV = if [ -e $(NIX_DAEMON_SH) ]; then . $(NIX_DAEMON_SH); fi; \
	PATH="$$PATH:$$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin"; export PATH

.DEFAULT_GOAL := apply
.PHONY: help apply update check

help: ## Show this list
	@echo "Usage: make [target] [TARGET=<arch|ubuntu|wsl-arch|wsl-ubuntu>] [YES=1]"
	@echo
	@grep -hE '^[a-z]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN { FS = ":.*## " } { printf "  make %-8s %s\n", $$1, $$2 }'
	@echo
	@echo "  TARGET=...  override the detected target (arch, ubuntu, wsl-arch, wsl-ubuntu)"
	@echo "  YES=1       rewrite flake.nix's user line without asking (unattended runs)"

apply: ## Set up this machine: first run bootstraps, later runs rebuild (default)
	@$(NIX_ENV); \
	target=$$("$(DETECT)" $(TARGET)) || exit 1; \
	reason=; \
	if ! command -v nix >/dev/null 2>&1; then \
		reason="Nix is not installed"; \
	elif ! command -v home-manager >/dev/null 2>&1; then \
		reason="home-manager is not active for this user"; \
	elif [ "$$(readlink -f "$$HOME/.dotfiles" 2>/dev/null)" != "$(ROOT)" ]; then \
		reason="~/.dotfiles does not point at this repo"; \
	fi; \
	if [ -n "$$reason" ]; then \
		echo "==> make: first run ($$reason), target $$target: running bootstrap.sh"; \
		"$(ROOT)/bootstrap.sh" $(if $(filter 1,$(YES)),--yes) "$$target" || exit 1; \
		echo "==> make: first run complete. Open a new shell (or: exec zsh) so Nix and the new environment are on PATH."; \
	else \
		echo "==> make: existing setup found, target $$target: running rebuild.sh"; \
		"$(ROOT)/rebuild.sh" "$$target"; \
	fi

update: ## Pull the latest repo state (fast-forward only), then apply
	@cd "$(ROOT)" || exit 1; \
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		echo "make update: $(ROOT) is not a git checkout." >&2; exit 1; \
	fi; \
	autostash=; \
	if [ -n "$$(git status --porcelain --untracked-files=no)" ]; then \
		if [ -z "$$(git status --porcelain --untracked-files=no | grep -v ' flake.nix$$')" ] && \
		   [ -z "$$(git diff -U0 -- flake.nix | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*user = ')" ]; then \
			echo "==> make update: keeping the local user line in flake.nix across the pull"; \
			autostash=--autostash; \
		else \
			echo "make update: refusing to pull, there are local changes to tracked files:" >&2; \
			git status --short --untracked-files=no >&2; \
			echo "Commit or stash them (git stash), then run make update again." >&2; \
			exit 1; \
		fi; \
	fi; \
	echo "==> make update: git pull --ff-only"; \
	git pull --ff-only $$autostash || { \
		echo "make update: could not fast-forward (diverged history, detached HEAD, or no upstream)." >&2; \
		echo "Resolve it with git (e.g. git pull --rebase), then run make again." >&2; \
		exit 1; \
	}
	@$(MAKE) --no-print-directory apply

check: ## Evaluate every homeConfiguration without applying anything
	@$(NIX_ENV); \
	if ! command -v nix >/dev/null 2>&1; then \
		echo "make check: Nix is not installed yet; run make first." >&2; exit 1; \
	fi; \
	echo "==> nix flake check"; \
	nix flake check "$(ROOT)" || exit 1; \
	names=$$(nix eval --raw "$(ROOT)#homeConfigurations" --apply 'c: builtins.concatStringsSep " " (builtins.attrNames c)') || exit 1; \
	for name in $$names; do \
		echo "==> evaluating homeConfigurations.$$name"; \
		nix eval --raw "$(ROOT)#homeConfigurations.$$name.activationPackage.drvPath" >/dev/null || exit 1; \
	done; \
	echo "==> make check: all configurations evaluate"
