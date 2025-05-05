# wgbastion

A NixOS module to turn a host into a bastion server that:

1. Accepts incoming connections to specific ports and routes them to destination IP/port pairs over one wireguard peer
2. Acts an an egress point / VPN to allow connections originating from the other end of the tunnel to the public internet.

# Use Case

I'm using this to route incoming connnections to a bastion machine hosted on Oracle Cloud to my local kubernetes cluster at home.
This effectively gives me a public IP for free that I can then use to point to a Kubernetes Service that the other wireguard endpoint
can route to.

1. Install NixOS on Oracle: https://mtlynch.io/notes/nix-oracle-cloud/
2. Include this module into your configuaration and set the values as approriate.
3. Some how set up the client peer to connect to this public wg instance, and ensure that machine can route to your kube cluster.

## Configuration

Set `wgbastion.config` to a complicated structure. See the option definition for an example.

## Implementation Details

These steps are implemented by `wgbastion`:

### Ingress & Egress

1. Configure the Wireguard module with one peer allowing all `AllowedIPs`. This enables routing to (and receiving packets from) any IP over the wireguard link.

### Ingress

1. Use `nftables` to select the proper IP destination to route packets toward (via dnat).
2. Use `ip rule` to select a new routing table for those packets.
3. Set up `ip route`s on that new table to point to the wireguard device.
4. Set the right settings for NixOS's firewall module to allow these incoming connections - both allowing the incoming packet and setting [`rpfilter`](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Documentation/networking/ip-sysctl.txt?h=v4.9#n1090) to `loose` via NixOs's [`networking.firewall.extraReversePathFilterRules`](https://search.nixos.org/options?query=networking.firewall.extraReversePathFilterRules).

### Egress

1. Use `nftables` to mark connections originating from the wireguard device and mark all packets in both directions.
2. Use `ip rule` to select a new routing table for packets with that mark (letting return packets only flow over wireguard)
