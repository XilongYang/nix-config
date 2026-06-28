{ pkgs, ... }:
let
  toggleIme = pkgs.writeShellApplication {
    name = "toggle-ime";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.macism
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      ENGLISH="com.apple.keylayout.ABC"
      CHINESE="com.apple.inputmethod.SCIM.WBX"
      JAPANESE="com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
      
      state_file="/tmp/toggle-ime-last-$USER"
      
      current="$(macism)"
      
      case "$current" in
        "$ENGLISH")
          if IFS= read -r saved < "$state_file" 2>/dev/null &&
             { [ "$saved" = "$CHINESE" ] || [ "$saved" = "$JAPANESE" ]; }; then
            macism "$saved"
          else
            macism "$CHINESE"
          fi
          ;;
      
        "$CHINESE" | "$JAPANESE")
          mkdir -p "$(dirname "$state_file")"
          printf '%s\n' "$current" > "$state_file"
          macism "$ENGLISH"
          ;;
      
        *)
          macism "$ENGLISH"
          ;;
      esac
    '';
  };
in
{
  home.packages = [ toggleIme ];
}
