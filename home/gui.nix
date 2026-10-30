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

  # dwm lives in its own repository, checked out (not managed) in ~/.local/src/dwm
  # so local builds and edits stay; its theme scripts are linked from there.
  dwmDir = "${config.home.homeDirectory}/.local/src/dwm";
  dwmScripts = [ "dwm-dark.sh" "dwm-light.sh" ];
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
  # atc switches Alacritty, tmux, btop and Neovim between dark and light; it is edited
  # in place like the config.
  // {
    ".local/bin/atc".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.local/bin/atc";
  }
  # btop's dark and light themes, which atc selects. Only the theme files are
  # linked: ~/.config/btop/btop.conf stays btop's own writable file (atc edits
  # its color_theme line), so the directory itself stays real.
  // {
    ".config/btop/themes/DWM-Pink-Dark.theme".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/btop/themes/DWM-Pink-Dark.theme";
    ".config/btop/themes/DWM-Pink-Light.theme".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/btop/themes/DWM-Pink-Light.theme";
  }
  # Session plumbing so Chromium and other portal clients follow the dark/light
  # switch: the portal backend preference, the hook that exports
  # DISPLAY/XAUTHORITY to the systemd user environment (x11-session-env, which
  # the X session start file has to call), and a check that the
  # portal answers. xdg-desktop-portal and xdg-desktop-portal-gtk come from the
  # distro, not from here.
  // {
    ".config/xdg-desktop-portal/portals.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/xdg-desktop-portal/portals.conf";
    ".local/bin/x11-session-env".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.local/bin/x11-session-env";
    ".local/bin/portal-color-scheme".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.local/bin/portal-color-scheme";
  }
  # The dwm-* scripts call atc and set dwm's colors.
  // lib.genAttrs (map (n: ".local/bin/${n}") dwmScripts) (t: {
    source = config.lib.file.mkOutOfStoreSymlink "${dwmDir}/docs/${baseNameOf t}";
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

  # Clone dwm once, when ~/.local/src/dwm is missing. An existing checkout is
  # never pulled, reset or overwritten. A failed clone (offline, say) only warns:
  # the dwm-* links stay dangling until the next rebuild.
  home.activation.dwmCheckout = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${dwmDir}" ]; then
      echo "Cloning dwm into ${dwmDir}"
      run mkdir -p "$(dirname "${dwmDir}")"
      if ! GIT_TERMINAL_PROMPT=0 run ${pkgs.git}/bin/git clone --quiet https://github.com/DrMeosch/dwm.git "${dwmDir}"; then
        echo "warning: could not clone dwm; the dwm-dark.sh and dwm-light.sh links will not work until a later rebuild succeeds" >&2
      fi
    fi
  '';
}
