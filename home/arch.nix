{ pkgs, ... }:

# Arch Linux specifics. Keep anything genuinely Arch-only here; the shared
# config lives in common.nix and gui.nix.
{
  # Packages are provided by Nix, so nothing distro-specific is required here
  # for the current setup. This file exists as the place for Arch-only tweaks
  # (e.g. a package that only makes sense on an Arch desktop).
}
