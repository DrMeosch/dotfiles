{
  description = "dotfiles - standalone home-manager for Arch Linux and Ubuntu, native or under WSL2";

  inputs = {
    # Pinned to the 26.05 release line, like the repo this was based on.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # The official Alacritty theme collection (TOML), pinned in flake.lock.
    # Not a flake, just a source tree; home/gui.nix links it into ~/.config/alacritty/themes.
    alacritty-theme = {
      url = "github:alacritty/alacritty-theme";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      # The account being configured is whoever runs the build: make, rebuild.sh and
      # bootstrap.sh export DOTFILES_USER / DOTFILES_HOME and pass --impure, because
      # builtins.getEnv sees nothing in pure evaluation (nix flake check, CI), where
      # the placeholder is used instead.
      envOr = name: default:
        let v = builtins.getEnv name; in if v == "" then default else v;
      user = envOr "DOTFILES_USER" "user";
      homeDir = envOr "DOTFILES_HOME" "/home/${user}";

      # All targets (Arch and Ubuntu, native or under WSL2) are 64-bit Intel/AMD.
      # Change to "aarch64-linux" for an ARM machine.
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      mkHome = modules:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit user homeDir inputs; };
          modules = [ ./home/common.nix ] ++ modules;
        };

      configs = {
        arch = mkHome [ ./home/gui.nix ./home/arch.nix ];
        ubuntu = mkHome [ ./home/gui.nix ./home/ubuntu.nix ];
        # Under WSL2 there is no local display, so no gui.nix.
        wsl-arch = mkHome [ ./home/wsl.nix ./home/arch.nix ];
        wsl-ubuntu = mkHome [ ./home/wsl.nix ./home/ubuntu.nix ];
      };
    in
    {
      # Build one of these with `make` or ./rebuild.sh (both auto-detect the
      # target), or directly:
      #   DOTFILES_USER=$(id -un) DOTFILES_HOME=$HOME USER=$(id -un) \
      #     home-manager switch --impure --flake ~/.dotfiles#<target>
      homeConfigurations = configs // {
        # Legacy name from when there was a single WSL2 target (it was Ubuntu).
        wsl = configs.wsl-ubuntu;
      };

      # The Windows-side files for a WSL2 machine (WinGet configuration, Windows
      # Terminal fragment, .wslconfig, setup.ps1). See windows/default.nix.
      packages.${system}.windows = import ./windows { inherit pkgs; };
    };
}
