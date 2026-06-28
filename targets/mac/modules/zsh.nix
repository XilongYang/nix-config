{
  programs.zsh = {
    shellAliases = {
      ls = "ls --color=auto";
    };

    initContent = ''
      export GPG_TTY=$(tty)
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
      export CLICOLOR=1
      export LSCOLORS=...
    '';
  };
}
