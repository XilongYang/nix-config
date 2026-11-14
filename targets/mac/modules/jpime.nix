{ config, lib, ... }:
let
  src = ../../../files/mac/jpime/jpime.swift;
  bin = "${config.home.homeDirectory}/.local/bin/jpime";
  # Records which source the installed binary was built from, so a switch that
  # did not touch jpime.swift skips the compile.
  stamp = "${config.xdg.dataHome}/jpime/source";
in
{
  # jpime toggles the Japanese input method (see files/mac/jpime/jpime.swift);
  # Karabiner runs it on ⌃⌥J. It is compiled with the system swiftc rather than
  # pkgs.swift: the nixpkgs toolchain is a heavy build on darwin and its Carbon
  # support is unverified, so this one step depends on Xcode Command Line Tools
  # being installed outside of Nix. SDKROOT / DEVELOPER_DIR are dropped from the
  # environment so nix-shell leftovers cannot point swiftc at the wrong SDK.
  home.activation.jpime = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x "${bin}" ] && [ "$(readlink "${stamp}" 2>/dev/null)" = "${src}" ]; then
      verboseEcho "jpime: up to date"
    else
      if [ ! -x /usr/bin/swiftc ] || ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
        errorEcho "jpime: /usr/bin/swiftc needs Xcode Command Line Tools (xcode-select --install)"
        exit 1
      fi
      run mkdir -p "${config.home.homeDirectory}/.local/bin" "$(dirname "${stamp}")"
      run env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -O -o "${bin}.tmp" ${src}
      run mv -f "${bin}.tmp" "${bin}"
      run ln -sfn ${src} "${stamp}"
    fi
  '';
}
