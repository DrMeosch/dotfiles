{ ... }:

# Ubuntu or Arch under WSL2. No local display, so no Alacritty/fonts (gui.nix is not
# imported for this target). The terminal is Windows Terminal on the host side;
# the font, color scheme and .wslconfig are set up there by windows/setup.ps1
# (`make windows` renders the files, setup.ps1 applies them from PowerShell).
{
  # Neovim's system clipboard on WSL2: win32yank on the Windows side. Neovim
  # auto-detects win32yank.exe on PATH through Windows interop, so
  # `clipboard = unnamedplus` just works. It is not packaged in nixpkgs for
  # Linux; windows/setup.ps1 installs it through the rendered WinGet
  # configuration (run `make windows` here, then setup.ps1 on Windows).

  # Open Linux-side URLs in the Windows default browser when wslu is installed
  # (Ubuntu: sudo apt install wslu; Arch: from the AUR). Uncomment if you want it:
  # home.sessionVariables.BROWSER = "wslview";

  # tmux copies go to the Windows clipboard via clip.exe through
  # the tmux-yank plugin (clip.exe is on PATH whenever Windows interop is
  # enabled - the default). win32yank is Neovim's provider.
}
