{ pkgs }:

# The Windows-side files, rendered from Nix. `nix build .#windows` gives a
# folder with:
#
#   configuration.winget            WinGet configuration (DSC) for `winget configure`
#   windows-terminal-fragment.json  Windows Terminal fragment: color scheme + profile
#   .wslconfig                      WSL2 settings, copied to %USERPROFILE%\.wslconfig
#   setup.ps1                       applies all of the above (and installs the font)
#
# `make windows` (inside WSL) builds it and copies it to Windows as real files:
# Windows apps cannot follow /nix/store symlinks over the WSL file share.
let
  inherit (pkgs) lib;

  # Keep in step with $FontFace in setup.ps1 and the family in alacritty.toml.
  fontFace = "GeistMono Nerd Font";

  # The same palette Alacritty uses, so the terminal looks alike on both sides.
  theme = (builtins.fromTOML (builtins.readFile ../home/.config/alacritty/themes/rose-pine-moon.toml)).colors;

  winget = {
    properties = {
      configurationVersion = "0.2.0";
      resources = [
        {
          # Neovim's clipboard bridge on WSL2 (not packaged in nixpkgs for Linux).
          resource = "Microsoft.WinGet.DSC/WinGetPackage";
          id = "win32yank";
          directives = {
            description = "Install win32yank";
            allowPrerelease = true;
          };
          settings = {
            id = "equalsraf.win32yank";
            source = "winget";
          };
        }
      ];
    };
  };

  terminalFragment = {
    schemes = [
      {
        name = "Rose Pine Moon";
        inherit (theme.primary) background foreground;
        cursorColor = theme.cursor.cursor;
        selectionBackground = theme.selection.background;
        inherit (theme.normal) black red green yellow blue cyan white;
        purple = theme.normal.magenta;
        brightBlack = theme.bright.black;
        brightRed = theme.bright.red;
        brightGreen = theme.bright.green;
        brightYellow = theme.bright.yellow;
        brightBlue = theme.bright.blue;
        brightPurple = theme.bright.magenta;
        brightCyan = theme.bright.cyan;
        brightWhite = theme.bright.white;
      }
    ];
    profiles = [
      {
        name = "WSL (dotfiles)";
        guid = "{7b0a6f0e-5d0c-4f4e-9d1b-3b6f5a1c2e84}";
        # The default WSL distro, starting in its home directory.
        commandline = "wsl.exe --cd ~";
        colorScheme = "Rose Pine Moon";
        font.face = fontFace;
      }
    ];
  };

  wslConfig = {
    experimental = {
      # Give unused memory back to Windows instead of keeping it cached.
      autoMemoryReclaim = "gradual";
      # New virtual disks shrink when files are deleted.
      sparseVhd = true;
    };
  };

  yaml = pkgs.formats.yaml { };
  json = pkgs.formats.json { };
in
pkgs.runCommand "dotfiles-windows" { } ''
  mkdir -p $out
  {
    echo '# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2'
    cat ${yaml.generate "configuration.winget" winget}
  } > $out/configuration.winget
  cp ${json.generate "windows-terminal-fragment.json" terminalFragment} $out/windows-terminal-fragment.json
  cp ${pkgs.writeText "wslconfig" (lib.generators.toINI { } wslConfig)} $out/.wslconfig
  cp ${./setup.ps1} $out/setup.ps1
''
