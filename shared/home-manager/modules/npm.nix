{ config, ... }:
{
  home.sessionVariables.NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";

  xdg.configFile."npm/npmrc".text = ''
    cache=${config.home.homeDirectory}/.local/state/npm/cache
    logs-dir=${config.home.homeDirectory}/.local/state/npm/logs
  '';
}
