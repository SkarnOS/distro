{
  /*
    firewall = {
      ports.tcp = lib.mkMerge [
        (lib.mkIf (cfg.master.enable && cfg.network.internal.interface != null) [
          {
            ports = [
              # etcd
              2379
              2380
            ];
            saddrs = cfg.master.hosts;
            interfaces = [ internalInterfaceName ];
          }
          # apiserver
          {
            ports = [ 6443 ];
            saddrs = [
              "192.168.8.0/21" # nodes
              "10.0.0.0/8" # pods/services
            ];
            interfaces = [ internalInterfaceName ];
          }
        ])
        [
          (lib.mkIf (cfg.master.enable && cfg.master.allowHelsinkiVpn) {
            interfaces = [
              "wg0"
              "nb-helsinki"
            ];
            ports = [ 6443 ] ++ lib.optional cfg.haapi.enable 6444;
          })
        ]
        (lib.mkIf (cfg.network.internal.interface != null) [
          # kubelet API
          {
            ports = [ 10250 ];
            interfaces = [ internalInterfaceName ];
          }
        ])
        (lib.mkIf (cfg.network.ingress.interface != null) [
          # kubelet API
          {
            ports = [
              "http"
              "https"
            ];
            interfaces = [ ingressInterfaceName ];
          }
        ])
      ];

      # Flannel Wireguard
      ports.udp = lib.mkIf (cfg.network.cni == "flannel" && cfg.network.internal.interface != null) [
        {
          ports = [ 51820 ];
          interfaces = [ internalInterfaceName ];
        }
      ];

      v4 = {
        input.preRules = lib.mkBefore [
          # Disables FIB blocking set by the VPN module
          (lib.mkIf (cfg.network.cni == "flannel") "iifname cni0 accept")
          (lib.mkIf (cfg.network.cni == "cilium") "iifname lxc* accept")
          (lib.mkIf (
            cfg.network.cni == "cilium"
          ) "iifname cilium_vxlan ip daddr 10.0.0.0/8 ip daddr 10.0.0.0/8 accept")
          # health checks and metrics
          (lib.mkIf (cfg.network.cni == "cilium")
            "iifname { cilium_wg0, ${internalInterfaceName} } tcp dport { 4240, 910, 9100, 9962-9965 } accept"
          )
          # VXLAN
          (lib.mkIf (cfg.network.cni == "cilium") "iifname cilium_wg0 udp dport 8472 accept")
          # Wireguard
          (lib.mkIf (cfg.network.cni == "cilium") "iifname ${internalInterfaceName} udp dport 51871 accept")

          # Nginx ingress controller admission
          (lib.mkIf (cfg.network.cni == "cilium") "iifname ${internalInterfaceName} tcp dport 8443 accept")

          # Flannel
          (lib.mkIf (cfg.network.cni == "flannel" && cfg.network.internal.interface != null)
            "iifname ${internalInterfaceName} ip saddr { ${lib.concatStringsSep ", " cfg.master.hosts} } tcp sport 6443 accept"
          )
          (lib.mkIf (cfg.network.cni == "flannel") "iifname flannel-wg ip saddr 10.0.0.0/8 accept") # idk why. has something to do with the webhooks
          (lib.mkIf (
            cfg.network.cni == "flannel"
          ) "iifname flannel-wg ip saddr 10.0.0.0/8 udp sport 53 accept") # idk why
          (lib.mkIf (
            cfg.network.cni == "flannel" && cfg.network.internal.interface != null
          ) "iifname ${internalInterfaceName} ip saddr 10.0.0.0/8 tcp sport 443 accept") # idk why
        ];

        forward.postRules =
          (lib.optionals (cfg.network.cni == "cilium") [
            "iifname { cilium_net, cilium_host } oifname cilium_host accept"
          ])
          ++ (lib.optionals (cfg.network.cni == "flannel") [
            # Pods to Foreign CPs (for CP nodes) or to any CP (for worker nodes).
            # Also allows access to port 10250 which is the kubelet API for the metrics server
            "iifname { cni0, flannel-wg } ip daddr 192.168.8.0/24 tcp dport { 443, 6443, 10250 } accept"
            "iifname flannel-wg oifname cni0 accept" # inter-pod communication
          ])
          ++
            # Allow traffic between pods
            (lib.optional (
              cfg.network.cni == "flannel"
            ) "ip saddr 10.0.0.0/8 ip daddr 10.0.0.0/8 iifname cni0 accept")
          ++ [
            # Allow access to our DNS
            "ip saddr 10.244.0.0/16 ip daddr { ${
              lib.concatStringsSep ", " (
                lib.take 3 (lib.filter (x: !(lib.hasInfix ":" x)) config.networking.nameservers)
              )
            } } udp dport 53 accept"
            # For troubleshooting forwarding errors
            "log prefix \"Forward drop: \""
          ];
      };

      # v6 is only available with Cilium
      v6 = lib.mkIf (cfg.network.cni == "cilium") {
        input.preRules = lib.mkBefore [
          # Disables FIB blocking set by the VPN module
          "iifname lxc* accept"
        ];
        forward.postRules = [
          "iifname {cilium_net, cilium_host } oifname cilium_host accept"
          # Allow access to our DNS
          "ip6 saddr fd08:4e1::/32 ip6 daddr { ${
            lib.concatStringsSep ", " (
              lib.take 3 (lib.filter (x: (lib.hasInfix ":" x)) config.networking.nameservers)
            )
          } } udp dport 53 accept"
          # For troubleshooting forwarding errors
          "log prefix \"Forward drop: \""
        ];
      };
    };
  */
}
