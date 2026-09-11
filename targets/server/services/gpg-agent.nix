{ pkgs, ... }:
{
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # Keep in sync with shared/home-manager/modules/gnupg.nix — the agent
  # process doesn't inherit home.sessionVariables (those only reach
  # interactive shells), so it needs its own GNUPGHOME override to find
  # keys after moving ~/.gnupg to ~/.config/gnupg.
  systemd.user.services.gpg-agent.environment.GNUPGHOME = "/home/xilong/.config/gnupg";
}
