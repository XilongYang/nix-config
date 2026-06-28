{ pkgs, ... }:
let
  nvimImeWatcher = pkgs.writeText "kitty-nvim-ime.py" ''
    import base64
    import os
    import subprocess

    ENGLISH = "com.apple.keylayout.ABC"
    MACISM = "${pkgs.macism}/bin/macism"
    STATE_FILE = f"/tmp/kitty-nvim-ime-last-{os.environ.get('USER', 'user')}"


    def _macism(*args):
        try:
            result = subprocess.run(
                (MACISM, *args),
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except Exception:
            return ""
        return result.stdout.strip()


    def _read_last():
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                return f.readline().strip()
        except OSError:
            return ""


    def _write_last(value):
        if value and value != ENGLISH:
            try:
                with open(STATE_FILE, "w", encoding="utf-8") as f:
                    f.write(value + "\n")
            except OSError:
                pass


    def _switch_to_normal():
        current = _macism()
        if current and current != ENGLISH:
            _write_last(current)
        if current != ENGLISH:
            _macism(ENGLISH)


    def _switch_to_insert():
        saved = _read_last()
        if saved and saved != ENGLISH:
            _macism(saved)


    def _value(data):
        value = data.get("value")
        if isinstance(value, bytes):
            return value.decode("utf-8", "ignore")
        value = value or ""
        if value in ("insert", "normal"):
            return value
        try:
            return base64.b64decode(value).decode("utf-8", "ignore")
        except Exception:
            return value


    def on_set_user_var(boss, window, data):
        if data.get("key") != "NVIM_MODE":
            return

        mode = _value(data)
        if mode == "insert":
            _switch_to_insert()
        elif mode == "normal":
            _switch_to_normal()
  '';
in
{
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrains Mono";
      size = 14;
    };
    settings = {
      touch_scroll_multiplier = 3.0;
      cursor_blink_interval = 0;
      enable_audio_bell = "no";
      foreground = "#a9b1d6";
      background = "#1a1b26";
      color0 = "#414868";
      color8 = "#414868";
      color1 = "#f7768e";
      color9 = "#f7768e";
      color2 = "#73daca";
      color10 = "#73daca";
      color3 = "#e0af68";
      color11 = "#e0af68";
      color4 = "#7aa2f7";
      color12 = "#7aa2f7";
      color5 = "#bb9af7";
      color13 = "#bb9af7";
      color6 = "#7dcfff";
      color14 = "#7dcfff";
      color7 = "#c0caf5";
      color15 = "#c0caf5";
      cursor = "#c0caf5";
      cursor_text_color = "#1a1b26";
      selection_foreground = "none";
      selection_background = "#28344a";
      url_color = "#9ece6a";
      active_border_color = "#3d59a1";
      inactive_border_color = "#101014";
      bell_border_color = "#e0af68";
      tab_bar_style = "fade";
      tab_fade = "1";
      active_tab_foreground = "#3d59a1";
      active_tab_background = "#16161e";
      active_tab_font_style = "bold";
      inactive_tab_foreground = "#787c99";
      inactive_tab_background = "#16161e";
      inactive_tab_font_style = "bold";
      tab_bar_background = "#101014";
    };

    extraConfig = ''
      watcher ${nvimImeWatcher}

      map cmd+h send_text all \x08
      map cmd+j send_text all \x0a
      map cmd+k send_text all \x0b
      map cmd+l send_text all \x0c
      map cmd+a send_text all \x01
      map cmd+e send_text all \x05
      map cmd+s send_text all \x13
      map cmd+w send_text all \x17
      map cmd+b send_text all \x02
      map cmd+f send_text all \x06
      map cmd+y send_text all \x19
    '';
  };
}
