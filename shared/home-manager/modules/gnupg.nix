{ config, ... }:
{
  home.sessionVariables.GNUPGHOME = "${config.xdg.configHome}/gnupg";
}
