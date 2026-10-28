{ config, pkgs, user, ... }:

# Ubuntu on WSL2. No local display, so no Alacritty/fonts (gui.nix is not
# imported for this target). The terminal is Windows Terminal on the host side;
# set the font and theme there.
{
  home.packages = with pkgs; [
    # Bridges the system clipboard to Windows. Neovim auto-detects win32yank on
    # PATH under WSL, so `clipboard = unnamedplus` just works with no extra config.
    win32yank
  ];

  # Open Linux-side URLs in the Windows default browser when wslu is installed
  # (sudo apt install wslu). Uncomment if you want it:
  # home.sessionVariables.BROWSER = "wslview";

  # tmux copies go to the Windows clipboard via the tmux-yank plugin, which
  # uses clip.exe (on PATH whenever Windows interop is enabled - the default).
  # win32yank above is Neovim's provider.
}
