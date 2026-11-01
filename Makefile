# Single entry point for applying this setup. See `make help`.
#
# Everything real happens in bootstrap.sh and rebuild.sh; this file only decides
# which one to run and keeps Nix reachable while doing so.
#
#   make                  first run on a machine: bootstrap.sh
#                         every later run:        rebuild.sh
#   make update           git pull --ff-only, then make apply
#                         (refuses while tracked files have local changes, except a modified or
#                         deleted flake.lock, which is kept as a copy and restored to the committed one first)
#   make check            evaluate all homeConfigurations and build the Windows files,
#                         apply nothing
#   make windows          WSL2 only: render the Windows-side files and copy them to
#                         %USERPROFILE%\.dotfiles-windows (setup.ps1 applies them there)
#
# Variables:
#   TARGET=<name>   arch, ubuntu, wsl-arch or wsl-ubuntu (default: detected)
#
# The account configured is the one running make (not root); nothing to set.

ROOT := $(shell cd "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))" && pwd -P)
DETECT := $(ROOT)/scripts/detect-target.sh
NIX_DAEMON_SH := /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# A fresh Nix install (or a non-login shell) leaves nix off PATH. Put it there
# for the recipe's own shell, so one `make` works right after installing Nix and
# in a shell that was opened before.
NIX_ENV = if [ -e $(NIX_DAEMON_SH) ]; then . $(NIX_DAEMON_SH); fi; \
	PATH="$$PATH:$$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin"; export PATH

.DEFAULT_GOAL := apply
.PHONY: help apply update check windows

help: ## Show this list
	@echo "Usage: make [target] [TARGET=<arch|ubuntu|wsl-arch|wsl-ubuntu>]"
	@echo
	@grep -hE '^[a-z]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN { FS = ":.*## " } { printf "  make %-8s %s\n", $$1, $$2 }'
	@echo
	@echo "  TARGET=...  override the detected target (arch, ubuntu, wsl-arch, wsl-ubuntu)"

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
		"$(ROOT)/bootstrap.sh" "$$target" || exit 1; \
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
	if [ -n "$$(git status --porcelain --untracked-files=no -- flake.lock)" ]; then \
		lockcopy=flake.lock.local-$$(date +%Y%m%d-%H%M%S); \
		echo "==> make update: flake.lock differs from the committed one; keeping your copy as $$lockcopy and restoring the committed lock for the pull"; \
		{ [ ! -e flake.lock ] || cp flake.lock "$$lockcopy"; } && git checkout HEAD -- flake.lock || exit 1; \
	fi; \
	if [ -n "$$(git status --porcelain --untracked-files=no)" ]; then \
		echo "make update: refusing to pull, there are local changes to tracked files:" >&2; \
		git status --short --untracked-files=no >&2; \
		echo "Commit or stash them (git stash), then run make update again." >&2; \
		exit 1; \
	fi; \
	echo "==> make update: git pull --ff-only"; \
	git pull --ff-only || { \
		echo "make update: could not fast-forward (diverged history, detached HEAD, or no upstream)." >&2; \
		echo "Resolve it with git (e.g. git pull --rebase), then run make again." >&2; \
		exit 1; \
	}
	@$(MAKE) --no-print-directory apply

check: ## Evaluate every homeConfiguration and build the Windows files, apply nothing
	@$(NIX_ENV); \
	if ! command -v nix >/dev/null 2>&1; then \
		echo "make check: Nix is not installed yet; run make first." >&2; exit 1; \
	fi; \
	echo "==> nix flake check"; \
	nix flake check --no-write-lock-file "$(ROOT)" || exit 1; \
	names=$$(nix eval --no-write-lock-file --raw "$(ROOT)#homeConfigurations" --apply 'c: builtins.concatStringsSep " " (builtins.attrNames c)') || exit 1; \
	for name in $$names; do \
		echo "==> evaluating homeConfigurations.$$name"; \
		nix eval --no-write-lock-file --raw "$(ROOT)#homeConfigurations.$$name.activationPackage.drvPath" >/dev/null || exit 1; \
	done; \
	echo "==> building packages.windows"; \
	out=$$(nix build --no-write-lock-file "$(ROOT)#windows" --no-link --print-out-paths) || exit 1; \
	for f in configuration.winget windows-terminal-fragment.json .wslconfig setup.ps1; do \
		[ -s "$$out/$$f" ] || { echo "make check: $$out/$$f is missing or empty" >&2; exit 1; }; \
	done; \
	echo "==> make check: all configurations evaluate, the Windows files build"

windows: ## WSL2: render the Windows files and copy them to %USERPROFILE%\.dotfiles-windows
	@$(NIX_ENV); \
	case "$$("$(DETECT)" $(TARGET))" in wsl|wsl-*) ;; \
	*) echo "make windows: run this inside a WSL2 distro; it copies the files to the Windows side." >&2; exit 1 ;; \
	esac; \
	for tool in nix cmd.exe wslpath; do \
		command -v $$tool >/dev/null 2>&1 || { echo "make windows: $$tool not found (Nix installed? Windows interop enabled?)" >&2; exit 1; }; \
	done; \
	out=$$(nix build --no-write-lock-file "$(ROOT)#windows" --no-link --print-out-paths) || exit 1; \
	winhome=$$(cd "$$(wslpath -u 'C:\')" && cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r'); \
	dest=$$(wslpath -u "$$winhome" 2>/dev/null)/.dotfiles-windows; \
	if [ -z "$$winhome" ] || [ "$$dest" = /.dotfiles-windows ]; then \
		echo "make windows: could not find the Windows profile folder." >&2; exit 1; \
	fi; \
	rm -rf "$$dest"; mkdir -p "$$dest" || exit 1; \
	cp -rL --no-preserve=mode,ownership "$$out"/. "$$dest"/ || exit 1; \
	printf '%s\n' "==> make windows: copied to $$winhome\\.dotfiles-windows"; \
	printf '%s\n' "    Now apply it from PowerShell on Windows:"; \
	printf '%s\n' "    powershell -ExecutionPolicy Bypass -File $$winhome\\.dotfiles-windows\\setup.ps1"
