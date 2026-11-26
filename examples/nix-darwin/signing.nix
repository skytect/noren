# Stable code signatures for the programs that hold privacy grants (Accessibility, Input
# Monitoring, Screen Recording). macOS ties a grant to the program's code signature, and nixpkgs
# builds are ad-hoc signed, so every update would ask again. Each program is copied to a fixed
# path and signed there with one certificate made on this Mac; its signature then reads "this
# name, signed by that certificate", which survives updates. yabai documents the same trick.
#
# `programs` is read by darwin.nix and home.nix too: everything that runs one of these runs its
# signed `path`.
{
  lib,
  pkgs,
  username,
  ...
}:
let
  # Each program: what to copy from the store, where the signed copy lives, and the launchd job to
  # restart onto a new copy (gui/UID/… for an agent, system/… for a daemon)
  programs = {
    aerospace = {
      source = "${pkgs.aerospace}/Applications/AeroSpace.app";
      path = "/Applications/AeroSpace.app";
      restart = "gui/$uid/org.nix-community.home.aerospace";
    };
    noren = {
      source = "${pkgs.noren}/Applications/Noren.app";
      path = "/Applications/Noren.app";
      restart = "gui/$uid/org.nix-community.home.noren";
    };
    kanata = {
      source = lib.getExe pkgs.kanata;
      path = "/Library/NixSigned/kanata";
      restart = "system/org.nixos.kanata";
    };
  };

  identity = "nix-local-codesign";
  stateDir = "/var/db/nix-local-codesign";
  keychain = "${stateDir}/signing.keychain-db";
  passwordFile = "${stateDir}/password";
  markers = "/Library/NixSigned"; # what each signed copy was made from

  sign = pkgs.writeShellScript "local-signing" ''
    set -euo pipefail
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    uid=$(id -u ${username})

    # The certificate, made once
    if [ ! -e "${keychain}" ] || [ ! -e "${passwordFile}" ]; then
      rm -rf "${stateDir}"
      mkdir -p "${stateDir}"
      chmod 700 "${stateDir}"
      (umask 077; openssl rand -hex 24 > "${passwordFile}")
      tmp=$(mktemp -d)
      openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -subj "/CN=${identity}" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:false" 2>/dev/null
      security create-keychain -p "$(cat "${passwordFile}")" "${keychain}"
      security set-keychain-settings "${keychain}"
      security unlock-keychain -p "$(cat "${passwordFile}")" "${keychain}"
      security import "$tmp/key.pem" -k "${keychain}" -T /usr/bin/codesign > /dev/null
      security import "$tmp/cert.pem" -k "${keychain}" > /dev/null
      security set-key-partition-list -S apple-tool:,apple: -s \
        -k "$(cat "${passwordFile}")" "${keychain}" > /dev/null
      rm -rf "$tmp"
    fi
    security unlock-keychain -p "$(cat "${passwordFile}")" "${keychain}"
    mkdir -p "${markers}"

    # sign_copy NAME SRC DST: true when DST was replaced by a newly signed copy of SRC. The copy is
    # signed beside DST and only then moved over it, so a failed signing keeps the previous copy
    sign_copy() {
      local marker="${markers}/.$1-src" src="$2" dst="$3" tmp
      [ "$(cat "$marker" 2>/dev/null)" != "$src" ] || return 1
      tmp="$(dirname "$dst")/.new-$(basename "$dst")"
      rm -rf "$tmp"
      cp -R "$src" "$tmp"
      chmod -R u+w "$tmp"
      codesign --force --deep --keychain "${keychain}" -s "${identity}" "$tmp" || {
        rm -rf "$tmp"
        echo "warning: signing $1 failed; keeping the previous copy" >&2
        return 1
      }
      rm -rf "$dst"
      mv "$tmp" "$dst"
      echo "$src" > "$marker"
    }

    # Same path, new binary: launchd keeps the old process, so restart it
    ${lib.concatStrings (
      lib.mapAttrsToList (name: p: ''
        if sign_copy ${name} "${p.source}" "${p.path}"; then
          launchctl kickstart -k "${p.restart}" 2>/dev/null || true
        fi
      '') programs
    )}
  '';
in
{
  _module.args.signed = programs;

  # A signing failure only warns: the programs keep their previous signed copies
  system.activationScripts.postActivation.text = ''
    ${sign} || echo "warning: local code signing failed" >&2
  '';
}
