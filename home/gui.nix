{ config, lib, pkgs, user, inputs, ... }:

# Shared desktop (X11/Wayland) bits for the Arch and Ubuntu targets.
# WSL2 does not import this - it has no local display.
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # Our own (hand-converted) themes, edited in place, and the upstream
  # collection pinned by the alacritty-theme flake input. Both end up in
  # ~/.config/alacritty/themes/ so general.import can name any of them. A name
  # present in both resolves to ours (the few clashes are not equivalent).
  ownThemesDir = ./.config/alacritty/themes;
  ownThemes = builtins.attrNames (builtins.readDir ownThemesDir);
  upstreamThemes = lib.filter (n: !(builtins.elem n ownThemes))
    (builtins.attrNames (builtins.readDir "${inputs.alacritty-theme}/themes"));
  themeTarget = n: ".config/alacritty/themes/${n}";

  # Theme switch scripts, linked into ~/.local/bin: atc switches Alacritty, tmux
  # and Neovim between dark and light, the dwm-* scripts call it.
  scripts = [ "atc" "dwm-dark.sh" "dwm-light.sh" ];
in
{
  home.packages = with pkgs; [
    alacritty
    nerd-fonts.geist-mono  # the font Alacritty and Neovim render in (family "GeistMono Nerd Font")
    fontconfig             # fc-list / fc-match, to check which fonts are installed
    # System-clipboard providers: Neovim's `unnamedplus` and tmux's
    # copy-to-os-clipboard both need one of these on Linux. xclip covers X11,
    # wl-clipboard covers Wayland; having both means yank/copy works whichever
    # session type you log into. (WSL2 uses win32yank/clip.exe instead.)
    xclip
    wl-clipboard
  ];

  fonts.fontconfig.enable = true;

  # Edit-in-place Alacritty config: the main file and our own themes are
  # symlinked into the repo checkout; the upstream themes are read-only links
  # into the Nix store. The directories themselves are real, so the two sets
  # can sit side by side (a new theme file in the repo needs a rebuild to get
  # its link; edits to an existing one do not).
  home.file = {
    ".config/alacritty/alacritty.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/alacritty/alacritty.toml";
  }
  // lib.genAttrs (map themeTarget ownThemes) (t: {
    source = config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/home/${t}";
  })
  // lib.genAttrs (map themeTarget upstreamThemes) (t: {
    source = "${inputs.alacritty-theme}/themes/${baseNameOf t}";
  })
  // lib.genAttrs (map (n: ".local/bin/${n}") scripts) (t: {
    source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/${t}";
  });

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  # An earlier layout linked the whole ~/.config/alacritty directory to the repo.
  # Linking the per-file entries above through that symlink would write them into
  # the checkout (alacritty.toml would become a link to itself), so drop the
  # symlink - only the link, never what it points to - before anything is linked.
  home.activation.migrateAlacrittyDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    if [ -L "$HOME/.config/alacritty" ]; then
      echo "Replacing the old ~/.config/alacritty symlink with a real directory"
      run rm "$HOME/.config/alacritty"
    fi
  '';

  # alacritty.toml imports current-theme.toml, which `atc` rewrites on every
  # switch (so it is mutable state, not a link). Seed it once with the default
  # theme so the first start is not left with Alacritty's plain default colors.
  home.activation.alacrittyCurrentTheme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ ! -e "$HOME/.config/alacritty/current-theme.toml" ]; then
      run mkdir -p "$HOME/.config/alacritty"
      run cp --no-preserve=mode "${ownThemesDir}/rose-pine-moon.toml" "$HOME/.config/alacritty/current-theme.toml"
    fi
  '';
}
