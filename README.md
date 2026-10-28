# dotfiles

Personal Linux setup managed with standalone [home-manager](https://nix-community.github.io/home-manager/).
One repo, one command (`make`), and a fresh machine ends up configured the same way every time - on
**Arch Linux** and **Ubuntu**, either native or under **WSL2**.

Based on [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles) (the Nix/home-manager
structure) with pieces from [DrMeosch/dotfiles](https://github.com/DrMeosch/dotfiles) (tmux, Alacritty themes).
The original base is a macOS nix-darwin config; this is reworked for Linux as **standalone
home-manager**, which manages your `$HOME` on any distro without needing NixOS.

## What you get

A `home-manager switch` builds:

- **Shell**: zsh with autosuggestions, syntax highlighting, fzf keybindings, and a [starship](https://starship.rs/) prompt (no oh-my-zsh, no powerlevel10k)
- **Multiplexer**: tmux (prefix `C-a`, vi keys) with plugins managed by [tpm](https://github.com/tmux-plugins/tpm), which the config clones and installs on first start (needs `git`)
- **Editor**: [LazyVim](https://www.lazyvim.org/)-based Neovim config (lazy.nvim, neogit, vimwiki, devcontainer LSP, neovide settings)
- **Terminal**: Alacritty with a collection of color themes (rose-pine moon by default) - desktop targets only
- **CLI tools**: ripgrep, fd, fzf, jq, lazygit, git, rustup, tree-sitter
- **Agent configs**: one shared `AGENTS.md` for Claude / Codex / opencode, plus Claude and Pi settings
- **Font**: Hack Nerd Font (desktop targets)

## Layout

```
Makefile             # the entry point: `make` (apply), `make update`, `make check`
flake.nix            # homeConfigurations: arch / ubuntu / wsl-arch / wsl-ubuntu (+ the one `user` line)
bootstrap.sh         # first run (called by make): install Nix, link ~/.dotfiles, first switch
rebuild.sh           # later runs (called by make): home-manager switch
scripts/
  detect-target.sh   # the one place that picks arch / ubuntu / wsl-arch / wsl-ubuntu
home/
  common.nix         # shared: packages, zsh, starship, tmux, agent configs, symlinks
  gui.nix            # desktop-only: Alacritty + fonts (arch, ubuntu)
  arch.nix           # Arch-only tweaks
  ubuntu.nix         # Ubuntu-only tweaks
  wsl.nix            # WSL2 (either distro): no GUI (clipboard bridge notes)
  .config/nvim/      # Neovim config (edited in place)
  .config/alacritty/ # alacritty.toml + themes/
  .tmux.conf         # tmux config (plugins via tpm)
  .tmux/             # tmux themes (dark/light.conf; current-theme.conf is seeded locally)
  AGENTS.md          # shared agent instructions
  .claude/ .pi/      # agent settings
.github/
  workflows/ci.yml   # CI: make + smoke test on Ubuntu, Arch, and Ubuntu on WSL2
  scripts/smoke-test.sh
  scripts/test-detect-target.sh
  scripts/test-make-update.sh
```

Config files are symlinked **out of the Nix store** (`mkOutOfStoreSymlink`), so you can edit
`home/.config/nvim/...`, `home/.tmux.conf`, `home/.config/alacritty/...` in place and the
change takes effect immediately - no rebuild needed. A rebuild is only needed when you change a
`.nix` file (packages, options).

## Prerequisites

- A 64-bit (`x86_64`) Arch or Ubuntu machine, native or under WSL2. For ARM, change `system` in `flake.nix` to `"aarch64-linux"`.
- `git`, `curl` and `make`:
  - Arch: `sudo pacman -S --needed git curl make`
  - Ubuntu: `sudo apt install git curl make`

## Fresh-machine setup

```sh
git clone https://github.com/<you>/dotfiles.git ~/dotfiles
cd ~/dotfiles
make
```

That is the whole setup. `make` (same as `make apply`) works out which of the four setups this is and
whether the machine has been set up before, and says on screen which path it took:

- **First run** (no `nix`, home-manager not yet active for your user, or `~/.dotfiles` not pointing at this repo): runs `bootstrap.sh`.
- **Every later run**: runs `rebuild.sh`.

The four targets are told apart in one place, `scripts/detect-target.sh`: WSL2 from `/proc/version`, the distro
from `ID` in `/etc/os-release`, falling back to the words of `ID_LIKE` so derivatives (EndeavourOS, Manjaro,
Pop!_OS, Linux Mint, ...) count as their parent. Anything else (another distro, macOS) stops with an error.

| Machine | Target |
| --- | --- |
| Native Arch Linux (e.g. a laptop) | `arch` |
| Native Ubuntu | `ubuntu` |
| Arch Linux under WSL2 | `wsl-arch` |
| Ubuntu under WSL2 | `wsl-ubuntu` |

Override the detection with `make TARGET=wsl-ubuntu`. `wsl` still works as an alias for `wsl-ubuntu`, the
only WSL target there was before the split.

### Native Arch Linux (laptop or desktop)

Nothing Arch-specific beyond the prerequisites. Nix comes from the [Determinate installer](https://github.com/DeterminateSystems/nix-installer)
(not from pacman), which sets up a systemd `nix-daemon` service, so:

```sh
sudo pacman -S --needed git curl make
git clone https://github.com/<you>/dotfiles.git ~/dotfiles
cd ~/dotfiles
make
```

The target is detected as `arch` (desktop: Alacritty and the Hack Nerd Font included). It asks before
touching `flake.nix` (see below); `make YES=1` skips the question.

### What the first run does

Through `bootstrap.sh`, in order:

1. Installs Determinate Nix if `nix` isn't present (flakes enabled). Nix is made available inside that same `make` call, so one command is enough even though your current shell does not have `nix` on `PATH` yet.
2. Symlinks this repo to `~/.dotfiles` (the config resolves edit-in-place paths through it).
3. Checks the `user` in `flake.nix` against your login name and offers to fix it (`make YES=1` accepts without asking, for unattended runs).
4. Runs the first `home-manager switch` for the detected target (existing files are backed up as `*.bak`).

When it finishes, **open a new shell** (or `exec zsh`) so Nix and the new environment are on `PATH`.

Then make zsh your login shell - home-manager installs zsh but cannot change your shell on a non-NixOS distro:

```sh
command -v zsh | sudo tee -a /etc/shells   # register the nix-profile zsh
chsh -s "$(command -v zsh)"                # set it as the login shell
```

Log out and back in (or `exec zsh`) to pick up the new environment.

> If a later run aborts with "would be clobbered by backing it up ... but ... already exists", delete the stale `*.bak` files it names and re-run: home-manager's `-b bak` refuses to overwrite an existing backup.

## Daily use

```sh
make                # edited a file in the repo? re-apply (rebuild.sh)
make update         # git pull --ff-only, then apply
make help           # list the commands
```

`make update` refuses to pull, and says why, when you have local changes to tracked files or your
history has diverged from the remote. The one local change it tolerates is the `user = ` line in
`flake.nix` that the first run may have rewritten; that edit is kept across the pull.

`make TARGET=...` and `make YES=1` work with every command.

### What make calls

`make` is a thin layer; the logic stays in the scripts, which you can still run yourself:

```sh
./bootstrap.sh [--yes] [target]   # first run: Nix, ~/.dotfiles link, username, first switch
./rebuild.sh [target]             # home-manager switch for the detected (or given) target
```

### Validate without applying

```sh
make check
```

Runs `nix flake check` and evaluates every homeConfiguration (`arch`, `ubuntu`, `wsl-arch`, `wsl-ubuntu`,
and the `wsl` alias) without building or applying anything.

### CI

`.github/workflows/ci.yml` runs the real `make` on every push to `master` and every pull request: a first
`make` that must take the bootstrap path, then a second `make` that must take the rebuild path, then
`.github/scripts/smoke-test.sh` (tools on `PATH` from the Nix profile, linked files resolve into the repo,
tmux loads `~/.tmux.conf` without errors, `nvim --headless +qa` exits 0). The Ubuntu job also runs
`make help` and `make check`, plus `.github/scripts/test-detect-target.sh`, which checks the four-way
target detection (including WSL2 Arch and Arch/Ubuntu derivatives) against fixture files, and
`.github/scripts/test-make-update.sh`, which drives `make update` against a throwaway origin. Jobs: `ubuntu` (ubuntu-latest), `arch`
(archlinux container) and `wsl` (Ubuntu 24.04 on real WSL2 on windows-latest, target `wsl-ubuntu`). Arch under WSL2 is not run
on a real WSL2 Arch distro in CI; its detection is covered by the fixture test and its configuration by
`make check`.

## Make it yours

- **Username**: `make` offers to set it on the first run, or change the single `user = "ag"` line in `flake.nix`. Everything (home directory, symlink paths) threads from it.
- **CPU architecture**: `system` in `flake.nix` (`x86_64-linux` by default; `aarch64-linux` for ARM).
- **Default terminal theme**: change the `general.import` line in `home/.config/alacritty/alacritty.toml` to any file in `home/.config/alacritty/themes/` (dracula, nord, gruvbox, night-owl, pink-moon, seoul256, ayu-light, firewatch, ...).

**Git identity** is deliberately not set, so each machine sets its own:

```sh
git config --global user.name "Your Name"
git config --global user.email you@example.com
```

To manage it declaratively instead, add to `home/common.nix` under `programs.git`:

```nix
settings.user.name = "Your Name";
settings.user.email = "you@example.com";
```

## Notes per target

- **Arch / Ubuntu desktop**: import `gui.nix`, so you get Alacritty and the Hack Nerd Font. Set your terminal font to "Hack Nerd Font".
- **WSL2 (Ubuntu or Arch)**: no local display, so no Alacritty/fonts. Set the font and colors in **Windows Terminal** on the host side. Neovim copies to the Windows clipboard via `win32yank`, which you install on the Windows side (`winget install equalsraf.win32yank`; it is not in nixpkgs for Linux); tmux copies via `clip.exe` through the tmux-yank plugin (it is on `PATH` whenever Windows interop is enabled - the default). For `wslview` as `$BROWSER`, install `wslu` (Ubuntu: `sudo apt install wslu`; Arch: from the AUR) and uncomment the line in `home/wsl.nix`.

## Rust

`rustup` is installed on every target and owns the toolchain (`cargo`, `rustc`, `rust-analyzer`); `~/.cargo/bin` is on `PATH` for `cargo install`ed binaries. Neovim uses LazyVim's Rust extra, which picks up `rust-analyzer` from `PATH` (Mason only installs the `codelldb` debugger). First-time setup after a switch:

```sh
rustup default stable
rustup component add rust-analyzer
```

Projects can pin their own toolchain with a `rust-toolchain.toml`.

## Differences from the source repos

- **Not** nix-darwin - this is standalone home-manager for Linux. No macOS system-defaults layer.
- **WezTerm** (base repo's terminal) is replaced by **Alacritty**; re-adding WezTerm is a few lines in `gui.nix` if you want it.
- **powerlevel10k / oh-my-zsh** (DrMeosch) are intentionally left out in favor of starship + native zsh plugins.
- The DrMeosch security/recon shell functions are **not** included.
- Alacritty themes were converted from the old YAML format to modern TOML.

## License

MIT - see [LICENSE](LICENSE).
