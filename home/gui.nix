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
  });
}
