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
      kitty-pop-kbd() { printf '\e[<u' }
      autoload -Uz add-zsh-hook
      add-zsh-hook precmd kitty-pop-kbd
    '';
    oh-my-zsh = {
      enable = true;
      theme = "kardan";
      plugins = [ "git" ];
    };
  };
}
