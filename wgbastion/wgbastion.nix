{
  config,
  lib,
  pkgs,
  ...
}: let
  #
  # Port forward from this host (the bastion) to remote IP destinations (portForwards) routed over wireguard network.
  #
  wg = config.wgbastion.config;
  forwardAll = pkgs.lib.sort (a: b: a < b) (pkgs.lib.unique (pkgs.lib.flatten (pkgs.lib.catAttrs "ports" (pkgs.lib.attrValues wg.portForward))));
  forwardCommaStr = pkgs.lib.strings.concatMapStringsSep "," builtins.toString forwardAll;
in {
  imports = [
  ];

  options = {
    wgbastion.config = lib.mkOption {
      type = lib.types.anything;
      description = "A complex structure defining the configuration";
      example = ''
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
      '';
    };
  };

  config = {
    assertions = [
    ];

    environment.systemPackages = [
      pkgs.wireguard-tools
    ];

    networking.nat.enable = true;
    networking.nat.externalInterface = wg.extDev;
    networking.nat.internalInterfaces = [wg.intDev];
    networking.firewall.logReversePathDrops = true;
    networking.firewall.extraReversePathFilterRules = "iifname ${wg.intDev} accept";
    networking.firewall = {
      allowedUDPPorts = [51820] ++ forwardAll;
      allowedTCPPorts = forwardAll;
    };

    networking.wireguard.enable = true;
    networking.wireguard.interfaces = {
      "${wg.intDev}" =
        {
          ips = ["${wg.bastion.ip}/${wg.bastion.mask}"];
          listenPort = 51820;

          allowedIPsAsRoutes = false;

          privateKeyFile = wg.bastion.privateKeyFile;

          peers = [
            {
              publicKey = wg.far.publicKey;
              #allowedIPs = ["${wg.far.ip}/${wg.far.mask}"];
              # So, once a packet hits the wg link, wg then looks up the dst IP of the packet to know which peer to send
              # it to. Setting this to :: tells it to route everything it gets to the peer.
              #
              # Unforuntately it also allows incoming IPs to appeaer to be from anywhere, but, eh, we dont route those by
              # default.
              allowedIPs = ["0.0.0.0/0" "::/0"];
            }
          ];
        }
        // (
          let
            writeNftScript = pkgs.writers.makeScriptWriter {interpreter = "${pkgs.nftables}/bin/nft -f";}; # Can't use check here because "netlink: Error: cache initialization failed: Operation not permitted" - check="${pkgs.nftables}/bin/nft -c -f"; };
            writeNftScriptTable = name: family: table: chains: (
              writeNftScript "/bin/${name}" (''
                  table ${family} ${table}
                  delete table ${family} ${table}
                ''
                + (
                  if chains != ""
                  then ''
                    table ${family} ${table} {
                    	${chains}
                    }
                  ''
                  else ""
                ))
            );
            tableCommands = dev: family: table: contents: {
              postSetup = pkgs.lib.meta.getExe (writeNftScriptTable "${dev}-postSetup" family table contents);
              postShutdown = pkgs.lib.meta.getExe (writeNftScriptTable "${dev}-postShutdown" family table "");
            };
            scripts = [
              (tableCommands wg.intDev "ip" "${wg.intDev}-table" (''

                                    # Policy Routing Strategy
                                    #
                                    # 1. Wg table ${wg.toTable}: All packets exit via wireguard
                                    #
                                    #      - Public ingress packets matching forward ports use this table (ct new) use this table and are dnat'd (regular port forwarding, essentially)
                                    #      - Public ingress reply packets (requested from wireguard) use this table and are marked with ${wg.toTable}
                                    #
                                    # 2. Default Table: All other packets exit normally
                                    #
                                    #      - Packets egressing from ${wg.intDev} get a ct packet mark. Future replies use the above table (${wg.toTable}).
                                    #

                                    ## Use this host as an ingress router / load balancer.

                                    	chain bastion-as-ingress {
						  comment "Use this host as an ingress router / load balancer / TCP+UDP L4 proxy for new connections from ${wg.extDev} (ports ${forwardCommaStr})";
                                                  type nat hook prerouting priority dstnat;
                                                  iifname ${wg.extDev} meta l4proto {tcp, udp} th dport { ${forwardCommaStr} } counter jump bastion-as-ingress-dnat
                                            }

                                                  chain bastion-as-ingress-dnat {
                                                  comment "Forward packets to the correct destinations based on port via dnat and routing table selection (via mark)";

                                                  meta mark set ${wg.toTable} comment "Mark originating packet as eventually destined for ${wg.intDev}. Replies will use the default routing table (back to internet)."

                ''
                + (pkgs.lib.strings.concatStringsSep "\n" (lib.attrsets.foldlAttrs (
                    acc: name: value:
                      acc
                      ++ ["# forward for ${name}" "meta l4proto {tcp, udp} th dport { ${pkgs.lib.strings.concatMapStringsSep "," builtins.toString value.ports}} counter dnat to ${value.dst} comment \"dnat for ${name}\"" ""]
                  ) []
                  wg.portForward))
                + ''
                              reject with icmp type host-prohibited;
                              }


                              # Use this host as a proxy
                              #
                              ## Below two chains set a conntrack mark on new connections from ${wg.intDev}, making sure return packets get the proper mark to head back to it

                              chain bastion-as-egress-mark-ct {
                                              comment "Use this host as an egress point (VPN) for new connections and mark the connection as originating from ${wg.intDev}"
                                              type nat hook prerouting priority mangle; policy accept;
                                              iifname == "${wg.intDev}" ct mark set ${wg.fromTable} counter comment "mark ct on connections from ${wg.intDev}"
                              }
                              chain bastion-as-egress-mark-return-ingress {
                                              comment "Mark each packet that belongs to a connection originating from ${wg.intDev}"
                                              type filter hook prerouting priority dstnat; policy accept;
                                              ct mark ${wg.fromTable} meta mark set ${wg.toTable} counter comment "for packets belonging to a marked connection, mark the incoming packet"
                              }
                ''))

              {
                postSetup = pkgs.lib.meta.getExe (pkgs.writeShellApplication {
                  name = "${wg.intDev}-postSetup-ip-rule";
                  runtimeInputs = [pkgs.nftables];
                  text =
                    ''
                      # ip rule helpers
                      has_rule() { F=$(ip rule show "$@"); test -n "$F"; };
                      add_rule() { ip rule add "$@"; };
                                    replace_rule() { has_rule "$@" || add_rule "$@"; };
                                    drop_rule() { (has_rule "$@" && ip rule delete "$@") || true; };

                                    # deprioritize local table lookup (needed to special case packets destined here)
                                    replace_rule lookup local priority 1000
                                    has_rule lookup local priority 1000 && drop_rule lookup local priority 0


                                    # from internet device ports to special routing table
                    ''
                    + (pkgs.lib.strings.concatStrings (pkgs.lib.lists.forEach forwardAll (prt: "replace_rule iif ${wg.extDev} dport ${toString prt} table ${wg.toTable} priority 100\n")))
                    + ''

                      replace_rule iif ${wg.extDev} fwmark ${wg.toTable} table ${wg.toTable}

                                                    # in special table, use wg device and route via far's ip
                                                    ip route replace default via ${wg.far.ip} dev ${wg.intDev} table ${wg.toTable}

                    '';
                });
              }
            ];
            mergeValues = name: values: builtins.concatStringsSep "\n" values;
          in
            pkgs.lib.attrsets.zipAttrsWith mergeValues scripts
        );
    };
  };
}
