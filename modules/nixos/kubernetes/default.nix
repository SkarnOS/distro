{
  config,
  options,
  pkgs,
  lib,
  helsinkiLib,
  ...
}:

let
  cfg = config.rename-me.kubernetes;
  internalInterfaceName =
    (if cfg.network.internal.interface == null then "dummy0" else cfg.network.internal.interface)
    + lib.optionalString (
      cfg.network.internal.vlanId != null
    ) ".${toString cfg.network.internal.vlanId}";
  ingressInterfaceName =
    cfg.network.ingress.interface
    + lib.optionalString (cfg.network.ingress.vlanId != null) ".${toString cfg.network.ingress.vlanId}";
in
{

  imports = [
    ./firewall.nix
    ./flannel.nix
    ./cilium.nix
  ];

  options.rename-me.kubernetes = {
    enable = lib.mkEnableOption "a kubeadm-managed Kubernetes node";

    upgradePackage = lib.mkOption {
      description = "A Kubernetes package from which `kubeadm` will be installed into PATH as `upgrade-kubeadm`";
      type = lib.types.nullOr lib.types.package;
      default = null;
    };

    setKubeconfig = lib.mkOption {
      description = "Whether or not to set the `KUBECONFIG` environment variable globally";
      type = lib.types.bool;
      default = true;
      example = false;
    };

    clusterName = lib.mkOption {
      description = "Name of this cluster";
      type = lib.types.singleLineStr;
    };

    elmaAudience = lib.mkOption {
      description = "When set, generates `/etc/kubernetes/oidc.yaml` with Elma configuration and the given audience";
      type = lib.types.nullOr lib.types.singleLineStr;
      default = null;
      example = "ec72ab96-36ab-4fd3-8cbd-5051868093fa";
    };

    encryptionProviderConfig = lib.mkOption {
      description = "When set, configures the given file on the host system as the encryption provider for the control plane";
      type = lib.types.nullOr lib.types.singleLineStr;
      default = null;
      example = "/run/secrets/k8s/encryption-provider.yaml";
    };

    network = {
      cni = lib.mkOption {
        description = "Name of the CNI the host will be prepared for. Note that cilium has to be used in kube-proxy replacement mode. There is no IPv6 for Flannel";
        type = lib.types.attrTag {
          # TODO: remove
          "flannel" = lib.mkOption {
            type = lib.types.submodule { };
            default = { };
          };
          "cilium" = lib.mkOption {
            type = lib.types.submodule { };
            default = { };
          };
        };
        default."cilium" = { };
      };

      dontConfigureNetworkd = lib.mkOption {
        description = "Support for legacy clusters that do their own networkd configuration";
        type = lib.types.bool;
        default = false;
        example = true;
      };

      internal = {
        interface = lib.mkOption {
          description = "Specify network interface where all Kubernetes nodes are connected to. Set to null if this is a single-node cluster. A dummy interface will be created in that case when using Cilium";
          type = lib.types.nullOr lib.types.singleLineStr;
          default = null;
          example = "eth0";
        };

        vlanId = lib.mkOption {
          description = "Number of a VLAN on the interface. If set, an appropriate VLAN configuration will be created";
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 4003;
        };

        extraNetworkdConfig = options.systemd.network.networks.type.getSubOptions [ ];
      };

      ingress = {
        interface = lib.mkOption {
          description = "Specify network interface where a load balancer ist connected to. Will be configured and firewall will be opened for port 80 and 443";
          type = lib.types.nullOr lib.types.singleLineStr;
          default = null;
          example = "eth0";
        };

        vlanId = lib.mkOption {
          description = "Number of a VLAN on the interface. If set, an appropriate VLAN configuration will be created";
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 4003;
        };

        extraNetworkdConfig = options.systemd.network.networks.type.getSubOptions [ ];
      };
    };

    master = {
      enable = lib.mkEnableOption "a kubeadm-managed Kubernetes master node";

      allowHelsinkiVpn = lib.mkEnableOption "access to the control plane from the Helsinki VPN";

      hosts = lib.mkOption {
        description = "IP addresses of the other hosts to open the firewall";
        type = lib.types.listOf lib.types.singleLineStr;
        default = [ ];
        example = [ "192.168.1.2" ];
      };
    };

    openebs.enable = lib.mkEnableOption "OpenEBS integration";

    ceph.enable = (lib.mkEnableOption "Rook-Ceph integration") // {
      default = true;
    };

    haapi = {
      enable = lib.mkEnableOption "the highly available API";

      masters = lib.mkOption {
        description = "Host-port pairs of masters that are available";
        type = lib.types.nonEmptyListOf lib.types.singleLineStr;
        default = [ ];
        example = [ "my-host:6443" ];
      };
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernel.sysctl = {
        # Module system foo, we set this to 1 twice
        "net.ipv4.ip_forward" = lib.mkForce 1;
        # Alloy
        "fs.inotify.max_user_watches" = lib.mkOverride 999 524288;
        "fs.inotify.max_user_instances" = lib.mkOverride 999 524288;
      }
      // lib.optionalAttrs cfg.openebs.enable {
        "vm.nr_hugepages" = lib.mkDefault 1024;
      };

      kernelModules =
        # Kubelet
        [
          "nft_compat"
          "xt_comment"
          "xt_conntrack"
        ]
        ++ (lib.optionals cfg.openebs.enable [
          "nvme-tcp"
        ])
        ++ lib.optionals cfg.ceph.enable [
          "ceph"
          "dm_crypt" # encrypted OSD
          "ext4"
          "nbd"
          "rbd"
        ];
    };

    environment.systemPackages =
      with pkgs;
      [
        # Makes the cluster manageable from any nodes
        jq
        kubectl
        kubernetes-helm
        # Gives us kubeadm and all dependencies for kubeadm init
        config.services.kubernetes.package
        cri-tools
        ethtool
        socat
        conntrack-tools
        iptables-nftables-compat
      ]
      ++ (lib.optionals (cfg.upgradePackage != null) [
        (pkgs.runCommand "kubeadm-upgrade" { inherit (cfg) upgradePackage; } ''
          mkdir -p $out/bin
          cp $upgradePackage/bin/kubeadm $out/bin/upgrade-kubeadm
        '')
      ]);

    services = {
      kubernetes = {
        roles = [ "node" ]; # we use a stacked control plane by default
        apiserverAddress = ""; # We set this using `kubeadm init`
        dataDir = "/var/lib/kubelet";
        kubelet = {
          registerNode = true; # why not?
          clusterDns =
            if (lib.versionAtLeast (lib.versions.majorMinor lib.version) "24.11") then [ "" ] else ""; # don't overwrite my DNS
          extraOpts = lib.escapeShellArgs [
            # allow having swap
            "--fail-swap-on=false"
            # use kubeadm init things
            "--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf"
            "--kubeconfig=/etc/kubernetes/kubelet.conf"
            "--config=/var/lib/kubelet/config.yaml"
            # Only use 3 DNS servers to prevent annoying warning
            "--resolv-conf=${
              pkgs.writeText "kubelet-resolv.conf" (
                lib.concatMapStringsSep "\n" (ns: "nameserver ${ns}") (lib.take 3 config.networking.nameservers)
              )
            }"
          ];
        };
        # Features we don't need on a stacked control plane
        proxy.enable = false;
        flannel.enable = false;
        pki.enable = false;
        easyCerts = false;
      };
      # High Availability API (kube-apiserver), we need this on all hosts
      haproxy = lib.mkIf cfg.haapi.enable {
        enable = lib.mkDefault true;
        package = lib.mkDefault pkgs.haproxy;
        config = ''
          ############## Configure Frontend #############
          frontend kube-apiserver
            mode tcp
            # bind to specific IPs, so that kube-apiserver from k8s can bind to 192.168.8.0/24 nodeIPs
            bind 127.0.0.1:6444
            default_backend kube-apiserver-tcp

          # https://www.haproxy.com/documentation/haproxy-configuration-tutorials/alerts-and-monitoring/prometheus/#configure-the-prometheus-exporter
          frontend prometheus
            mode http
            http-request use-service prometheus-exporter if { path /metrics }
            no log

          ############## Configure Backend #############
          # servers that fulfill the requests
          backend kube-apiserver-tcp
            mode tcp
            # balance, one of: roundrobin,static-rr,leastconn,first,source,uri,url_param,hdr(<name>),rdp-cookie,rdp-cookie(<name>)
            # here: try to come out at kube-apiserver-1, till maxconn is reached
            balance first

            # health-checks:
            # might need to increase global.tune.chksize 32768
            option httpchk GET /readyz?verbose HTTP/1.0
            http-check expect string 'etcd ok'

            default-server verify none check-ssl inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
            ${lib.concatStringsSep "\n  " (
              lib.imap1 (num: host: "server kube-apiserver-${toString num} ${host} check") cfg.haapi.masters
            )}
        '';
      };
    };

    environment = {
      variables = lib.mkIf cfg.setKubeconfig { KUBECONFIG = "/etc/kubernetes/admin.conf"; };
      etc = {
        "cni/net.d".enable = false; # Let kubeadm handle this
        # Setting a mode forces this to not be a symlink, because we cannot resolve symlinks to /nix in containers
        "ssl/certs/ca-certificates.crt".mode = "0444";
        /*
          "kubernetes/stop-node".source = ./stop-node;
          "kubernetes/elma-crb.yaml".source = ./elma-crb.yaml;
          "kubernetes/oidc.yaml" = lib.mkIf (cfg.elmaAudience != null) {
            # No symlink
            mode = "0444";
            text = # yaml
              ''
                ---
                apiVersion: apiserver.config.k8s.io/v1beta1
                kind: AuthenticationConfiguration
                jwt:
                - issuer:
                    url: https://elma.id
                    audiences:
                    - ${cfg.elmaAudience}
                    audienceMatchPolicy: MatchAny
                  claimMappings:
                    username:
                      claim: "sub"
                      prefix: "elma:"
                    groups:
                      claim: "groups"
                      prefix: "elma:"
              '';
          };
        */
        "kubernetes/kubeadm-cp-init.yaml".text = ''
          ---
          apiVersion: kubeadm.k8s.io/v1beta4
          kind: InitConfiguration
          localAPIEndpoint:
            advertiseAddress: ${builtins.head (builtins.match "([^,]+).*" config.services.kubernetes.kubelet.nodeIp)}
            bindPort: 6443
          nodeRegistration:
            criSocket: unix:///run/containerd/containerd.sock
          ---
          apiVersion: kubeadm.k8s.io/v1beta4
          kind: ClusterConfiguration
          clusterName: ${cfg.clusterName}
          kubernetesVersion: ${config.services.kubernetes.package.version}
          controlPlaneEndpoint: "127.0.0.1:${if cfg.haapi.enable then "6444" else "6443"}"
          networking:
            dnsDomain: ${cfg.clusterName}.k8s.helsinki.tools
            podSubnet: 10.224.0.0/11,fd08:4e1:1::/52
            serviceSubnet: 10.96.0.0/12,fd08:4e1:2::/108
          controllerManager:
            extraArgs:
              - name: node-cidr-mask-size-ipv4
                value: "21"
              - name: node-cidr-mask-size-ipv6
                value: "62"
          apiServer:
            extraArgs:
          ${lib.optionalString (cfg.elmaAudience != null) ''
            #
              - name: authentication-config
                value: /oidc.yaml
              - name: authorization-mode
                value: Node,RBAC
          ''}
          ${lib.optionalString (cfg.encryptionProviderConfig != null) ''
            #
              - name: feature-gates
                value: StructuredAuthenticationConfiguration=true
              - name: encryption-provider-config
                value: /encryption-provider.yaml
          ''}
            extraVolumes:
          ${lib.optionalString (cfg.elmaAudience != null) ''
            #
              - hostPath: /etc/kubernetes/oidc.yaml
                mountPath: /oidc.yaml
                name: oidc-config
                pathType: File
                readOnly: true
          ''}
          ${lib.optionalString (cfg.encryptionProviderConfig != null) ''
            #
              - hostPath: ${cfg.encryptionProviderConfig}
                mountPath: /encryption-provider.yaml
                name: encryption-config
                pathType: File
                readOnly: true
          ''}
            certSANs: [ "127.0.0.1", "::1", "api.${cfg.clusterName}.k8s.helsinki.tools"${
              lib.concatMapStringsSep "" (ip: ", \"${ip}\"") cfg.master.hosts
            } ]
          proxy:
            disabled: true
          ---
          apiVersion: kubelet.config.k8s.io/v1beta1
          kind: KubeletConfiguration
          serverTLSBootstrap: true
        '';
      };
    };

    # helsinki = {
    #   #monitoring.hostConfig.vars.dns_resolver_enable = true;

    #   /*
    #     disko.mountOptions."/" = lib.mkIf cfg.ceph.enable [ "dev" ];

    #     monitoring.hostConfig.vars.extra_filesystems_ignore_dests = [
    #       "^${config.services.kubernetes.dataDir}/plugins/.*"
    #       "^${config.services.kubernetes.dataDir}/pods/.*"
    #       "^/run/containerd/.*"
    #     ];

    #     heb = {
    #       paths = [ "/etc/kubernetes/" ];
    #       excludes = [
    #         "${config.services.kubernetes.dataDir}/"
    #         "/var/lib/containerd/"
    #       ];
    #     };
    #   */

    #   # TODO promtail
    # };

    # Workaround: https://github.com/ceph/ceph/pull/60006#issuecomment-2834332814
    services.udev.extraRules =
      let
        splitDmName = pkgs.writeShellScript "split-dm-name" ''
          echo "''${DM_NAME%%-*}/''${DM_NAME#*-}"
        '';
      in
      lib.mkIf cfg.ceph.enable ''
        KERNEL=="dm-*", ENV{DM_NAME}=="*-*_rimage_*", PROGRAM="${splitDmName} %E{DM_NAME}", SYMLINK+="%c"
        KERNEL=="dm-*", ENV{DM_NAME}=="*-*_rmeta_*", PROGRAM="${splitDmName} %E{DM_NAME}", SYMLINK+="%c"
      '';

    systemd.services = {
      kubelet = {
        stopIfChanged = false;
        # Ensures we have the right iptables flavor
        path = lib.mkBefore [ pkgs.iptables-nftables-compat ];

        # Don't crash-loop the daemon
        unitConfig.AssertFileNotEmpty = [
          "|/etc/kubernetes/bootstrap-kubelet.conf"
          "|/etc/kubernetes/kubelet.conf"
        ];

        /*
                apparmor = {
                  enable = false;
                  extraConfig = ''
                    ${config.environment.etc.os-release.source} r,
                    /dev/disk/** r,
                    /dev/kmsg rw,
                    /etc/machine-id r,
                    /run/containerd/containerd.sock rw,
                    /run/mount/utab r,
                    /run/systemd/private rw,
                    /run/dbus/system_bus_socket rw,
                    /run/xtables.lock rwklm,
                    /sys/** r, # It really needs a lot of info
                    /sys/fs/cgroup/** rwklm,
                    @{PROC}/diskstats r,
                    @{PROC}/loadavg r,
                    @{PROC}/swaps r,
                    @{PROC}/sys/kernel/** r, # It really needs a lot of info
                    @{PROC}/sys/kernel/panic rw,
                    @{PROC}/sys/vm/** r, # It really needs a lot of info
                    @{PROC}/sys/vm/overcommit_memory rw,
                    @{PROC}@{pid}/** rw,
                    deny /nix/store/ r,

                    # This would normally be in ReadWritePaths, but that would create a new
                    # mount namespace which would prevent us from doing containerd things
                    /etc/kubernetes/** rwklm,
                    /opt/cni/bin/ r,
                    /opt/cni/bin/** rwklm,
                    ${config.services.kubernetes.dataDir}/** rwklm,
                    /var/log/pods/ r,
                    /var/log/pods/** rwklm,
                    /var/log/containers/ r,
                    /var/log/containers/** rwklm,
                    /usr/libexec/** rwklm,
                    /tmp/** rwixklm,
                    /run/current-system/kernel-modules/lib/modules/** r,
                    /run/booted-system/kernel-modules/lib/modules/** r,
                    /nix/store/** r,
                    ${lib.optionalString cfg.openebs.enable ''
                      /home/keys/ rwklm,
                      /home/keys/** rwklm,
                      /var/openebs/** rwklm,
                      /var/openebs/local/** rwklm,
                      /var/local/openebs/io-engine/ rwklm,
                      /var/local/openebs/io-engine/** rwklm,
                      /sys/kernel/mm/hugepages/ r,
                      /sys/kernel/mm/hugepages/** r,
                    ''}

                    capability chown,
                    capability dac_override,
                    capability dac_read_search,
                    capability fowner,
                    capability net_admin,
                    capability sys_admin,
                    capability sys_ptrace,
                    capability sys_resource,
                    capability syslog,

                    ptrace (read, readby) peer=@{profile_name},
                    ptrace (read, readby) peer=unconfined, # whatever

                    mount ${config.services.kubernetes.dataDir}/pods/**,
                    umount ${config.services.kubernetes.dataDir}/pods/**,

                    network udp,
                    network tcp,
                    network netlink raw,
                  '';
                };
        */
      };
    };

    # Cluster DNS
    services.dnsdist = {
      enable = false;
      extraConfig = # lua
      ''
        -- Set listen interfaces
        setLocal("0.0.0.0:53", { reusePort=true })
        addLocal("[::]:53", { reusePort=true })

        -- stfu
        setSecurityPollSuffix("")

        -- Set ACL
        setACL("0.0.0.0/0")
        addACL("[::]/0")

        -- Add servers
      ''
      /*
        + lib.concatMapStringsSep "\n" (
          hostname: # lua
          ''
            newServer({
                address="${lib.head helsinkiLib.hosts."${hostname}".v6}",
                name="${lib.removeSuffix config.helsinki.wg.helsinki.meta.dnsSuffix hostname}",
                useClientSubnet=true,
                -- Health check
                checkInterval=10,
                mustResolve=true
            })
          '') config.helsinki.wg.helsinki.meta.resolverHosts
        # lua
      */
      + ''
        -- create pool
        getPool("kubernetes")

        newServer({
            address="10.96.0.10",
            pool="kubernetes";
            useClientSubnet=true,
            -- Health check
            checkInterval=10,
            mustResolve=true
        })

        kubernetesSuffix = newSuffixMatchNode()
        kubernetesSuffix:add("cluster.local")
        reverseSuffix = newSuffixMatchNode()
        reverseSuffix:add("10.in-addr.arpa")
        addAction(SuffixMatchNodeRule(kubernetesSuffix), PoolAction("kubernetes"))
        addAction(SuffixMatchNodeRule(reverseSuffix), PoolAction("kubernetes"))
      '';
    };
    networking = {
      nameservers = [ "127.0.0.1" ];
      search = lib.mkDefault [
        "default.svc.cluster.local"
        "svc.cluster.local"
        "cluster.local"
      ];
    };

    systemd = {
      tmpfiles.rules = [
        "d /etc/kubernetes/manifests 0700 root root -"
        "d /var/lib/kubelet/pods 0755 kubernetes kubernetes -"
        "d /var/lib/kubelet/plugins_registry 0755 kubernetes kubernetes -"
        "d /var/log/containers 0750 root root -"
        "d /var/log/pods 0750 root root -"
        "d /usr/libexec 0755 root root -"
      ];

      # Dummy interface for single-node clusters
      network.netdevs = lib.mkMerge [
        (lib.mkIf ((!cfg.network.dontConfigureNetworkd) && cfg.network.internal.vlanId != null) (
          lib.listToAttrs [
            (helsinkiLib.networkd.vlanToNetdev cfg.network.internal.interface "" {
              id = cfg.network.internal.vlanId;
            })
          ]
        ))

        (lib.mkIf ((!cfg.network.dontConfigureNetworkd) && cfg.network.ingress.vlanId != null) (
          lib.listToAttrs [
            (helsinkiLib.networkd.vlanToNetdev cfg.network.ingress.interface "" {
              id = cfg.network.ingress.vlanId;
            })
          ]
        ))
      ];

      network.networks = lib.mkMerge [
        (lib.mkIf ((!cfg.network.dontConfigureNetworkd) && cfg.network.internal.vlanId != null) {
          "${cfg.network.internal.interface}".vlan = [ internalInterfaceName ];
        })
        (lib.mkIf ((!cfg.network.dontConfigureNetworkd) && cfg.network.ingress.vlanId != null) {
          "${cfg.network.ingress.interface}".vlan = [ ingressInterfaceName ];
        })
        (lib.mkIf (!cfg.network.dontConfigureNetworkd) {
          "${internalInterfaceName}" = {
            matchConfig.Name = internalInterfaceName;
            DHCP = lib.mkDefault "no";
          };
          other.enable = lib.mkDefault false;
        })
        (lib.mkIf (!cfg.network.dontConfigureNetworkd && cfg.network.ingress.interface != null) {
          "${ingressInterfaceName}" = {
            matchConfig.Name = ingressInterfaceName;
            DHCP = lib.mkDefault "no";
          };
          other.enable = lib.mkDefault false;
        })
        (lib.mkIf (!cfg.network.dontConfigureNetworkd) {
          "${internalInterfaceName}" = cfg.network.internal.extraNetworkdConfig;
        })
        (lib.mkIf (!cfg.network.dontConfigureNetworkd && cfg.network.ingress.interface != null) {
          "${ingressInterfaceName}" = cfg.network.ingress.extraNetworkdConfig;
        })
      ];
    };
  };
}
