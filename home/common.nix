{ config, pkgs, user, ... }:

let
  # Config files live in the repo and are symlinked out of the Nix store so you
  # can edit them in place and have changes take effect without a rebuild.
  # bootstrap.sh symlinks the repo to ~/.dotfiles, which is what these resolve against.
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  home.username = user;
  home.homeDirectory = "/home/${user}";
  home.stateVersion = "24.11";

  # Required on non-NixOS distros (Arch, Ubuntu, WSL2): wires up session
  # variables, man pages, and /etc profile integration for home-manager.
  targets.genericLinux.enable = true;

  # Let home-manager manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    jq        # json on the command line
    lazygit
    neovim
    tmux
    # Note: fzf, git and starship are installed by their programs.* blocks below,
    # so they are not repeated here.
  ];

  home.sessionVariables.EDITOR = "nvim";

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      share = false;                   # DrMeosch's setup kept per-shell history
    };
    initContent = ''
      bindkey '^f' autosuggest-accept
    '';
    shellAliases = {
      ".." = "cd ..";
      ll = "ls -lah";
      v = "nvim -p";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  # fzf keybindings (Ctrl-R history, Ctrl-T files) and completion in zsh.
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Git is installed above; identity is deliberately left unset so each machine
  # sets its own. See the README ("Git identity") to manage it declaratively.
  programs.git = {
    enable = true;
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # Edit-in-place: the real files stay in the repo, ~/ and ~/.config point at them.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";

  # tmux: vendored gpakosz config + a .local override file you own.
  home.file.".tmux.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.tmux.conf";
  home.file.".tmux.conf.local".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.tmux.conf.local";

  # Shared agent instructions for Claude / Codex / opencode, plus Claude settings.
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Keep Pi's credential and runtime state local by linking only authored files.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";
}
