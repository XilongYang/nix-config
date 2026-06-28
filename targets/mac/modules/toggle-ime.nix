{ pkgs, ... }:
let
  toggleIme = pkgs.writeShellApplication {
    name = "toggle-ime";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.macism
    ];
    text = ''
      set -euo pipefail

      ENGLISH="com.apple.keylayout.ABC"
      CHINESE="com.apple.inputmethod.SCIM.WBX"
      JAPANESE="com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}"
      state_file="$state_dir/toggle-ime-last"

      mkdir -p "$state_dir"

      current="$(macism)"
      last_ime="$CHINESE"

      if [ -f "$state_file" ]; then
        saved="$(cat "$state_file")"
        if [ "$saved" = "$CHINESE" ] || [ "$saved" = "$JAPANESE" ]; then
          last_ime="$saved"
        fi
      fi

      case "$current" in
        "$ENGLISH")
          macism "$last_ime"
          ;;
        "$CHINESE" | "$JAPANESE")
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
