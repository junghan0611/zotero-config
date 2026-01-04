# Zotero Translation Server - NixOS/Home-Manager Configuration
#
# This file provides multiple ways to run the Zotero Translation Server:
# 1. Docker container via Home-Manager
# 2. Podman container (rootless)
# 3. Direct Node.js execution (requires manual setup)
#
# Usage:
#   Add to your Home-Manager or NixOS configuration
#

{ config, pkgs, lib, ... }:

let
  # Configuration options
  cfg = config.services.zotero-translation-server;
in
{
  options.services.zotero-translation-server = {
    enable = lib.mkEnableOption "Zotero Translation Server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1969;
      description = "Port to run the Translation Server on";
    };

    useDocker = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use Docker to run the server (recommended)";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the server automatically on login";
    };
  };

  config = lib.mkIf cfg.enable {
    # Option 1: Docker-based service (recommended)
    systemd.user.services.zotero-translation-server = lib.mkIf cfg.useDocker {
      Unit = {
        Description = "Zotero Translation Server";
        After = [ "docker.service" ];
        Requires = [ "docker.service" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.docker}/bin/docker pull zotero/translation-server";
        ExecStart = "${pkgs.docker}/bin/docker run --rm --name zotero-translation -p ${toString cfg.port}:1969 zotero/translation-server";
        ExecStop = "${pkgs.docker}/bin/docker stop zotero-translation";
        Restart = "on-failure";
        RestartSec = "10s";
      };

      Install = lib.mkIf cfg.autoStart {
        WantedBy = [ "default.target" ];
      };
    };

    # Add environment variable for easy access
    home.sessionVariables = {
      ZOTERO_TRANSLATION_SERVER = "http://localhost:${toString cfg.port}";
    };
  };
}

# =============================================================================
# Alternative: Standalone systemd user service (without NixOS module)
# =============================================================================
#
# Create ~/.config/systemd/user/zotero-translation-server.service:
#
# [Unit]
# Description=Zotero Translation Server
# After=docker.service
# Requires=docker.service
#
# [Service]
# Type=simple
# ExecStart=/usr/bin/docker run --rm --name zotero-translation -p 1969:1969 zotero/translation-server
# ExecStop=/usr/bin/docker stop zotero-translation
# Restart=on-failure
# RestartSec=10s
#
# [Install]
# WantedBy=default.target
#
# Then run:
#   systemctl --user daemon-reload
#   systemctl --user enable --now zotero-translation-server
#
# =============================================================================
# Alternative: Podman (rootless containers)
# =============================================================================
#
# For NixOS with Podman:
#
# systemd.user.services.zotero-translation-server = {
#   Unit.Description = "Zotero Translation Server (Podman)";
#   Service = {
#     Type = "simple";
#     ExecStart = "${pkgs.podman}/bin/podman run --rm --name zotero-translation -p 1969:1969 docker.io/zotero/translation-server";
#     ExecStop = "${pkgs.podman}/bin/podman stop zotero-translation";
#     Restart = "on-failure";
#   };
#   Install.WantedBy = [ "default.target" ];
# };
#
# =============================================================================
# Quick Start Commands
# =============================================================================
#
# Docker (one-liner):
#   docker run -d -p 1969:1969 --name zotero-translation --restart unless-stopped zotero/translation-server
#
# Podman:
#   podman run -d -p 1969:1969 --name zotero-translation zotero/translation-server
#
# Test:
#   curl -X POST -H "Content-Type: text/plain" -d "https://arxiv.org/abs/2103.00020" http://localhost:1969/web
#
