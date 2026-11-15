{ config, ... }:
{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      xnix-gc = "sudo nix store gc --debug";
      vim = "nvim";
      pd = "curl -F \"c=@-\" \"https://fars.ee/\"";
      kiln = "nix run --refresh github:XilongYang/kiln";
    };
    initContent = ''
      PATH=$PATH:$HOME/.local/bin
      stty -ixon
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6b7280'
      # Clear terminal modes after ssh disconnect.
      kitty-reset-modes() {
        printf '\e[<u\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l'
      }
      autoload -Uz add-zsh-hook
      add-zsh-hook precmd kitty-reset-modes
    '';
    oh-my-zsh = {
      enable = true;
      theme = "kardan";
      plugins = [ "git" ];
    };
  };
}
