{
  config,
  lib,
  pkgs,
  ...
}: {
  wgbastion.config = {
    extDev = "enp0s6";
    intDev = "wg0";
    toTable = "1337";
    fromTable = "1338";
    bastion = {
      ip = "30.100.0.1";
      mask = "24";
      privateKeyFile = "/etc/nixos/wg-key.private";
    };
    far = {
      ip = "30.100.0.2";
      mask = "24";
      publicKey = builtins.readFile "/etc/nixos/wg-peer-far.pub";
    };
    portForward = {
      traefik = {
        ports = [80 8080 443];
        dst = "10.52.228.10";
      };
      jellyfin = {
        ports = [8096];
        dst = "10.52.228.20";
      };
    };
  };
}
