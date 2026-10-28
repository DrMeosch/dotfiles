# dotfiles

Personal Linux setup managed with standalone [home-manager](https://nix-community.github.io/home-manager/).
One repo, one command, and a fresh machine ends up configured the same way every time - on
**Arch Linux**, **Ubuntu**, and **Ubuntu on WSL2**.

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
flake.nix            # homeConfigurations: arch / ubuntu / wsl (+ the one `user` line)
bootstrap.sh         # fresh machine: install Nix, link ~/.dotfiles, first switch
rebuild.sh           # daily use: home-manager switch (auto-detects the target)
home/
  common.nix         # shared: packages, zsh, starship, tmux, agent configs, symlinks
  gui.nix            # desktop-only: Alacritty + fonts (arch, ubuntu)
  arch.nix           # Arch-only tweaks
  ubuntu.nix         # Ubuntu-only tweaks
  wsl.nix            # WSL2: no GUI (clipboard bridge notes)
  .config/nvim/      # Neovim config (edited in place)
  .config/alacritty/ # alacritty.toml + themes/
  .tmux.conf         # tmux config (plugins via tpm)
  .tmux/             # tmux themes (dark/light.conf; current-theme.conf is seeded locally)
  AGENTS.md          # shared agent instructions
  .claude/ .pi/      # agent settings
.github/
  workflows/ci.yml   # CI: bootstrap + smoke test on Ubuntu, Arch, and Ubuntu on WSL2
  scripts/smoke-test.sh
```

Config files are symlinked **out of the Nix store** (`mkOutOfStoreSymlink`), so you can edit
`home/.config/nvim/...`, `home/.tmux.conf`, `home/.config/alacritty/...` in place and the
change takes effect immediately - no rebuild needed. A rebuild is only needed when you change a
`.nix` file (packages, options).

## Prerequisites

- A 64-bit (`x86_64`) Arch, Ubuntu, or WSL2-Ubuntu machine. For ARM, change `system` in `flake.nix` to `"aarch64-linux"`.
- `curl` and `git` (Ubuntu: `sudo apt install curl git`; Arch: `sudo pacman -S curl git`).

## Fresh-machine setup

```sh
git clone https://github.com/<you>/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` detects the target (arch/ubuntu/wsl - override with `./bootstrap.sh <target>`) and, in order:

1. Installs [Determinate Nix](https://github.com/DeterminateSystems/nix-installer) if `nix` isn't present (flakes enabled).
2. Symlinks this repo to `~/.dotfiles` (the config resolves edit-in-place paths through it).
3. Checks the `user` in `flake.nix` against your login name and offers to fix it (`./bootstrap.sh --yes` accepts without asking, for unattended runs).
4. Runs the first `home-manager switch` for the detected target (existing files are backed up as `*.bak`).

Then make zsh your login shell - home-manager installs zsh but cannot change your shell on a non-NixOS distro:

```sh
command -v zsh | sudo tee -a /etc/shells   # register the nix-profile zsh
chsh -s "$(command -v zsh)"                # set it as the login shell
```

Log out and back in (or `exec zsh`) to pick up the new environment.

> If a later run aborts with "would be clobbered by backing it up ... but ... already exists", delete the stale `*.bak` files it names and re-run: home-manager's `-b bak` refuses to overwrite an existing backup.

## Daily use

Edit files in the repo, then apply:

```sh
./rebuild.sh            # auto-detects arch/ubuntu/wsl
./rebuild.sh ubuntu     # or force a target
```

### Validate without applying

```sh
nix flake check
nix build .#homeConfigurations.arch.activationPackage --dry-run   # or ubuntu / wsl
```

### CI

`.github/workflows/ci.yml` runs the real `bootstrap.sh --yes` on every push to `master` and every pull
request, then `rebuild.sh`, then `.github/scripts/smoke-test.sh` (tools on `PATH` from the Nix profile,
linked files resolve into the repo, tmux loads `~/.tmux.conf` without errors, `nvim --headless +qa`
exits 0). Jobs: `ubuntu` (ubuntu-latest), `arch` (archlinux container) and `wsl` (Ubuntu 24.04 on
real WSL2 on windows-latest).

## Make it yours

- **Username**: `./bootstrap.sh` offers to set it, or change the single `user = "ag"` line in `flake.nix`. Everything (home directory, symlink paths) threads from it.
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
- **WSL2**: no local display, so no Alacritty/fonts. Set the font and colors in **Windows Terminal** on the host side. Neovim copies to the Windows clipboard via `win32yank`, which you install on the Windows side (`winget install equalsraf.win32yank`; it is not in nixpkgs for Linux); tmux copies via `clip.exe` through the tmux-yank plugin (it is on `PATH` whenever Windows interop is enabled - the default). For `wslview` as `$BROWSER`, `sudo apt install wslu` and uncomment the line in `home/wsl.nix`.

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
