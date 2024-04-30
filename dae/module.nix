{ config, lib, pkgs, ... }:

let
  cfg = config.services.dae;
  assets = cfg.assets;
  genAssetsDrv = paths: pkgs.symlinkJoin {
    name = "dae-assets";
    inherit paths;
  };
in
{
  # disables Nixpkgs dae module to avoid conflicts
  disabledModules = [ "services/networking/dae.nix" ];

  options = {
    services.dae = with lib;{
      enable = mkEnableOption
        "dae, a Linux high-performance transparent proxy solution based on eBPF";

      package = mkOption {
        defaultText = lib.literalMD "`packages.dae` from this flake";
      };

      assets = mkOption {
        type = with types;(listOf path);
        default = with pkgs; [ v2ray-geoip v2ray-domain-list-community ];
        defaultText = literalExpression "with pkgs; [ v2ray-geoip v2ray-domain-list-community ]";
        description = "Assets required to run dae.";
      };

      assetsPath = mkOption {
        type = types.str;
        default = "${genAssetsDrv assets}/share/v2ray";
        defaultText = literalExpression ''
          "$\{(symlinkJoin {
              name = "dae-assets";
              paths = assets;
          })}/share/v2ray"
        '';
        description = ''
          The path which contains geolocation database.
          This option will override `assets`.
        '';
      };

      openFirewall = mkOption {
        type = with types; submodule {
          options = {
            enable = mkEnableOption ("opening {option}`port` in the firewall");
            port = mkOption {
              type = types.port;
              description = ''
                Port to be opened. Consist with field `tproxy_port` in config file.
              '';
            };
          };
        };
        default = {
          enable = true;
          port = 12345;
        };
        defaultText = literalExpression ''
          {
            enable = true;
            port = 12345;
          }
        '';
        description = ''
          Open the firewall port.
        '';
      };

      configFile = mkOption {
        type = with types; (nullOr path);
        default = null;
        example = "/path/to/your/config.dae";
        description = ''
          The path of dae config file, end with `.dae`.
          Will fallback to `/etc/dae/config.dae` if this is not set.
        '';
      };

      config = mkOption {
        type = with types; (nullOr str);
        default = null;
        description = ''
          WARNING: This option will expose your config unencrypted world-readable in the nix store.
          Config text for dae.

          See <https://github.com/daeuniverse/dae/blob/main/example.dae>.
        '';
      };

      disableTxChecksumIpGeneric =
        mkEnableOption "" // { description = "See <https://github.com/daeuniverse/dae/issues/43>"; };

    };
  };

  config = lib.mkIf cfg.enable
    (lib.mkMerge [
      (lib.mkIf (cfg.configFile == null)
        {
          environment.etc."dae/config.dae" = {
            mode = "0400";
            source = pkgs.writeText "config.dae" cfg.config;
          };
        })
      {
        environment.systemPackages = [ cfg.package ];
        systemd.packages = [ cfg.package ];

        networking = lib.mkIf cfg.openFirewall.enable {
          firewall =
            let portToOpen = cfg.openFirewall.port;
            in
            {
              allowedTCPPorts = [ portToOpen ];
              allowedUDPPorts = [ portToOpen ];
            };
        };

        systemd.services.dae =
          let
            daeBin = lib.getExe cfg.package;

            TxChecksumIpGenericWorkaround = with lib;
              (getExe pkgs.writeShellApplication {
                name = "disable-tx-checksum-ip-generic";
                text = with pkgs; ''
                  iface=$(${iproute2}/bin/ip route | ${lib.getExe gawk} '/default/ {print $5}')
                  ${lib.getExe ethtool} -K "$iface" tx-checksum-ip-generic off
                '';
              });

            configPath = if cfg.configFile != null then cfg.configFile else "/etc/dae/config.dae";
          in
          {
            wantedBy = [ "multi-user.target" ];
            reloadTriggers = [ cfg.config ];
            serviceConfig = {
              ExecStartPre = [ "" "${daeBin} validate -c ${configPath}" ]
                ++ (with lib; optional cfg.disableTxChecksumIpGeneric TxChecksumIpGenericWorkaround);
              ExecStart = [ "" "${daeBin} run --disable-timestamp -c ${configPath}" ];
              Environment = "DAE_LOCATION_ASSET=${cfg.assetsPath}";
              TimeoutStartSec = 120;
            };
          };

        assertions = [
          {
            assertion = lib.pathExists (toString (genAssetsDrv cfg.assets) + "/share/v2ray");
            message = ''
              Packages in `assets` has no preset path `/share/v2ray` included.
              Please set `assetsPath` instead.
            '';
          }

          {
            assertion = !((config.services.dae.config != null)
              && (config.services.dae.configFile != null));
            message = ''
              Option `config` and `configFile` could not be set at the same time.
            '';
          }

          {
            assertion = !((config.services.dae.config == null)
              && (config.services.dae.configFile == null));
            message = ''
              Either `config` or `configFile` should be set.
            '';
          }
        ];
      }
    ]);
}
