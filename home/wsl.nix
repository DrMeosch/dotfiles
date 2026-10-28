{ ... }:

# Ubuntu or Arch under WSL2. No local display, so no Alacritty/fonts (gui.nix is not
# imported for this target). The terminal is Windows Terminal on the host side;
# the font is installed there by windows/setup.ps1 (run it from PowerShell on
# the Windows side); set the theme there too.
{
  # Neovim's system clipboard on WSL2: install win32yank on the Windows side
  # (winget install equalsraf.win32yank). Neovim auto-detects win32yank.exe on
  # PATH through Windows interop, so `clipboard = unnamedplus` just works. It is
  # not packaged in nixpkgs for Linux, so it cannot be installed from here.

  # Open Linux-side URLs in the Windows default browser when wslu is installed
  # (Ubuntu: sudo apt install wslu; Arch: from the AUR). Uncomment if you want it:
  # home.sessionVariables.BROWSER = "wslview";

  # tmux copies go to the Windows clipboard via clip.exe through
  # the tmux-yank plugin (clip.exe is on PATH whenever Windows interop is
  # enabled - the default). win32yank is Neovim's provider.
}
