{
  description = "dotfiles - standalone home-manager for Arch Linux, Ubuntu, and Ubuntu on WSL2";

  inputs = {
    # Pinned to the 26.05 release line, like the repo this was based on.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your login name differs.
      user = "ag";

      # All three targets (Arch, Ubuntu, WSL2) are 64-bit Intel/AMD.
      # Change to "aarch64-linux" for an ARM machine.
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      mkHome = modules:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit user; };
          modules = [ ./home/common.nix ] ++ modules;
        };
    in
    {
      # Build one of these with ./rebuild.sh (it auto-detects the target) or
      #   home-manager switch --flake ~/.dotfiles#<target>
      homeConfigurations = {
        arch = mkHome [ ./home/gui.nix ./home/arch.nix ];
        ubuntu = mkHome [ ./home/gui.nix ./home/ubuntu.nix ];
        wsl = mkHome [ ./home/wsl.nix ];
      };
    };
}
