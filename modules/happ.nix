# SPDX-License-Identifier: GPL-3.0-only
# Happ client + its root daemon (happd) for TUN mode.
# Based on https://github.com/MrShitFox/happ-nixos (GPL-3.0).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.happ;
in
{
  options.services.happ = {
    enable = lib.mkEnableOption "Happ proxy client and its TUN daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/happ/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../pkgs/happ/package.nix { }";
      description = "The Happ package to use.";
    };

    tunInterface = lib.mkOption {
      type = lib.types.str;
      default = "tun0";
      description = "TUN device Happ brings up; trusted by the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Happ derives its HWID from /var/lib/dbus/machine-id, which dbus-broker (NixOS default) never creates.
    systemd.tmpfiles.rules = [ "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id" ];

    # TUN mode routes asymmetrically; strict reverse-path filtering would drop its replies.
    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ cfg.tunInterface ];
    boot.kernelModules = [ "tun" ];

    # Happ hard-codes /opt/happ. Materialise the store tree there, root-owned and read-only
    # for everyone else (happd runs it as root), refreshed only when the package changes.
    system.activationScripts.happ-opt = lib.stringAfter [ "stdio" ] ''
      stamp=/opt/happ/.nix-store-path
      if [ "$(cat "$stamp" 2>/dev/null)" != "${cfg.package}" ]; then
        rm -rf /opt/happ
        mkdir -p /opt/happ
        cp -r ${cfg.package}/happ/. /opt/happ/
        chown -R root:root /opt/happ
        chmod -R u=rwX,go=rX /opt/happ
        printf '%s' "${cfg.package}" > "$stamp"
      fi
    '';

    # Mirrors the vendor unit. No sandboxing: it spawns sing-box/tun2proxy as root to create the TUN device.
    systemd.services.happd = {
      description = "Happ Process Control Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      # ExecStart is a fixed /opt path, so tie restarts to the package explicitly.
      restartTriggers = [ cfg.package ];
      path = with pkgs; [
        iproute2
        iptables
        procps
        net-tools
      ];
      serviceConfig = {
        ExecStart = "/opt/happ/bin/happd";
        # A newer client makes happd exit 0 on purpose so systemd re-execs the upgraded binary.
        Restart = "always";
        RestartSec = "5s";
        TimeoutStopSec = "10s";
        KillMode = "mixed";
      };
    };
  };
}
