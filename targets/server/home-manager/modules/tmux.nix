{
  programs.tmux = {
    enable = true;

    extraConfig = ''
      set -g status off
      set -g set-clipboard on
      set -as terminal-features ',xterm-256color:clipboard'
      set -as terminal-features ',screen-256color:clipboard'
      set -as terminal-features ',tmux-256color:clipboard'
      set -as terminal-features ',rxvt-unicode-256color:clipboard'
    '';
  };
}
