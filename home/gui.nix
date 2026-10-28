{ config, pkgs, user, ... }:

# Shared desktop (X11/Wayland) bits for the Arch and Ubuntu targets.
# WSL2 does not import this - it has no local display.
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
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

  # Edit-in-place Alacritty config (main file + the themes/ collection).
  home.file.".config/alacritty".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/alacritty";
}
