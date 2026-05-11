{ inputs }:
{
  config,
  options,
  pkgs,
  lib,
  helsinkiLib,
  ...
}:

let
  cfg = config.skarnos.kubernetes;
  internalInterfaceName =
    (if cfg.network.internal.interface == null then "dummy0" else cfg.network.internal.interface)
    + lib.optionalString (
      cfg.network.internal.vlanId != null
    ) ".${toString cfg.network.internal.vlanId}";
  ingressInterfaceName =
    cfg.network.ingress.interface
    + lib.optionalString (cfg.network.ingress.vlanId != null) ".${toString cfg.network.ingress.vlanId}";

  kubeadmConfig = pkgs.writeText "kubeadm-config.yaml" ''
    ---
    apiVersion: kubeadm.k8s.io/v1beta4
    kind: InitConfiguration
    localAPIEndpoint:
      ${lib.optionalString (config.services.kubernetes.kubelet.nodeIp != null)
        "advertiseAddress: ${builtins.head (builtins.match "([^,]+).*" config.services.kubernetes.kubelet.nodeIp)}"
      }

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
      # dnsDomain: ${cfg.clusterName}.k8s.helsinki.tools
      podSubnet: ${cfg.network.podSubnet},fd08:4e1:1::/52
      serviceSubnet: ${cfg.network.serviceSubnet},fd08:4e1:2::/108
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
        lib.concatMapStringsSep "" (ip: ", \"${ip}\"") cfg.role.controlPlane.hosts
      } ]
    proxy:
      disabled: ${if cfg.network.kubeProxy then "false" else "true"}
    dns:
      disabled: ${if cfg.network.coredns then "false" else "true"}
    ---
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    serverTLSBootstrap: true
  '';
in
{

  imports = [
    (lib.modules.importApply ./cilium.nix { inherit inputs; })
    ./flannel.nix
    ./openebs.nix
    (lib.modules.importApply ./nix-snapshotter.nix { inherit inputs; })
  ];

  options.skarnos.kubernetes = {
    enable = lib.mkEnableOption "a kubeadm-managed Kubernetes node";

    package = lib.mkPackageOption pkgs "kubernetes" { } // {
      default = throw "You must select a Kubernetes version from the supported versions provided by SkarnOS.";
    };

    sshTarget = lib.mkOption {
      type = lib.types.str;
    };

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
      podSubnet = lib.mkOption {
        type = lib.types.str;
        description = ''
          CIDR range where pods will live.
        '';
      };

      serviceSubnet = lib.mkOption {
        type = lib.types.str;
        description = ''
          CIDR range where services will live.
        '';
      };

      kubeProxy = lib.mkEnableOption "Whether to enable the `kube-proxy`." // {
        default = true;
      };

      coredns = lib.mkEnableOption "Whether to enable `coredns`." // {
        default = true;
      };

      cni = lib.mkOption {
        description = "Name of the CNI the host will be prepared for. Note that cilium has to be used in kube-proxy replacement mode. There is no IPv6 for Flannel";
        type = lib.types.attrTag {
          # TODO: remove
          "flannel" = lib.mkOption {
            type = lib.types.submodule { };
            default = { };
          };
        };
        default."cilium" = { };
      };

      nameservers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default =
          if config.networking.nameservers != [ ] then
            lib.take 3 config.networking.nameservers
          else
            [
              "8.8.8.8"
              "8.8.4.4"
            ];
      };

      dontConfigureNetworkd =
        lib.mkEnableOption "Support for legacy clusters that do their own networkd configuration"
        // {
          default = false;
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

    role = {
      controlPlane = {
        enable = lib.mkEnableOption "a kubeadm-managed Kubernetes control-plane node";

        hosts = lib.mkOption {
          description = "IP addresses of the other hosts to open the firewall";
          type = lib.types.listOf lib.types.singleLineStr;
          default = [ ];
          example = [ "192.168.1.2" ];
        };

        sudoPreserveKubeconfig = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to preserve the `KUBECONFIG` environment variable through sudo.
          '';
        };
      };

      worker = {
        enable = lib.mkEnableOption "a kubeadm-manager Kubernetes worker node";
      };
    };

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
    security =
      let
        extraConfig = ''

          # Keep kube configuration location for root and %wheel.
          Defaults:root,%wheel env_keep+=KUBECONFIG
        '';
      in
      lib.mkIf cfg.role.controlPlane.sudoPreserveKubeconfig {
        sudo = { inherit extraConfig; };
        sudo-rs = { inherit extraConfig; };
      };

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
        inputs."self".legacyPackages.${pkgs.stdenv.hostPlatform.system}.fish-out-netif-ip
      ]
      ++ (lib.optional (cfg.upgradePackage != null) (
        pkgs.runCommand "kubeadm-upgrade" { inherit (cfg) upgradePackage; } ''
          mkdir -p $out/bin
          cp $upgradePackage/bin/kubeadm $out/bin/upgrade-kubeadm
        ''
      ));

    systemd.services.kubelet.serviceConfig.EnvironmentFile = "/var/lib/kubelet/kubeadm-flags.env";

    services = {
      kubernetes = {
        package = cfg.package;
        roles = [ "node" ]; # we use a stacked control plane by default
        apiserverAddress = ""; # We set this using `kubeadm init`
        dataDir = "/var/lib/kubelet";
        kubelet = {
          registerNode = true; # why not?
          clusterDns =
            if (lib.versionAtLeast (lib.versions.majorMinor lib.version) "24.11") then [ "" ] else ""; # don't overwrite my DNS
          extraOpts =
            (lib.escapeShellArgs [
              # allow having swap
              "--fail-swap-on=false"
              # use kubeadm init things
              "--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf"
              "--kubeconfig=/etc/kubernetes/kubelet.conf"
              "--config=/var/lib/kubelet/config.yaml"
              # Only use 3 DNS servers to prevent annoying warning
              "--resolv-conf=${
                pkgs.writeText "kubelet-resolv.conf" (
                  lib.concatMapStringsSep "\n" (ns: "nameserver ${ns}") cfg.network.nameservers
                )
              }"
            ])
            + " $KUBELET_KUBEADM_ARGS";
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
      };
    };

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

    systemd.services."kubelet" = {
      stopIfChanged = false;
      # Ensures we have the right iptables flavor
      path = lib.mkBefore [ pkgs.iptables-nftables-compat ];

      requiredBy = [ "kubernetes-full.target" ];
      before = [ "kubernetes-full.target" ];

      # Don't crash-loop the daemon
      unitConfig.AssertFileNotEmpty = [
        "|/etc/kubernetes/bootstrap-kubelet.conf"
        "|/etc/kubernetes/kubelet.conf"
      ];
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

    systemd.targets."kubernetes-full" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
    };

    systemd.services."kubernetes-image-preload" = {
      requiredBy =
        (lib.optional cfg.role.controlPlane.enable "kubeadm-init.service")
        ++ (lib.optional cfg.role.worker.enable "kubeadm-join.service");
      before =
        (lib.optional cfg.role.controlPlane.enable "kubeadm-init.service")
        ++ (lib.optional cfg.role.worker.enable "kubeadm-join.service");
      after = [ "containerd.service" ];

      script =
        let
          containerImages = pkgs.writers.writeText "container-images" (
            lib.concatMapStringsSep "\n" ({ name, value }: lib.concatStringsSep "\n" value) (
              lib.mapAttrsToList lib.nameValuePair config.services.kubernetes.package.passthru.containers
            )
          );
        in
        "${lib.getExe pkgs.parallel} -- ${lib.getExe' pkgs.containerd "ctr"} -n k8s.io image import < ${containerImages}";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
      };
    };

    # containerd defaults to the ZFS snapshotter, that's no longer needed as ZFS works
    # with overlayfs since semi-recently
    virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".containerd.snapshotter =
      lib.mkOverride 101 "overlayfs";

    systemd.services."kubeadm-join" =
      lib.mkIf (cfg.role.worker.enable || cfg.role.controlPlane.enable)
        {
          path = [
            config.services.kubernetes.package
            pkgs.util-linux
            pkgs.yq-go
            pkgs.jq
            pkgs.iproute2
            inputs."self".legacyPackages.${pkgs.stdenv.hostPlatform.system}.fish-out-netif-ip
          ];

          environment."KUBECONFIG" = "/etc/kubernetes/admin.conf";

          unitConfig.ConditionPathExists = "/var/lib/kubeadm-join/secret.env";

          serviceConfig = {
            RuntimeDirectory = "kubeadm-join";
            StateDirectory = "kubeadm-join";
            EnvironmentFile = "/var/lib/kubeadm-join/secret.env";
            Type = "oneshot";
            RemainAfterExit = "yes";
          };

          script = ''
            set -eEuo pipefail

            _config="/etc/kubernetes/kubeadm-config.yaml"
            cp ${kubeadmConfig} "$_config"

            cat >> "$_config" <<-EOF
            ---
            apiVersion: kubeadm.k8s.io/v1beta4
            kind: JoinConfiguration
            discovery:
              tlsBootstrapToken: "$JOIN_TOKEN"
              bootstrapToken:
                token: "$JOIN_TOKEN"
                apiServerEndpoint: "$CONTROL_PLANE_ADDRESS:6443"
                caCertHashes: [ "$DISCOVERY_TOKEN_CA_CERT_HASH" ]
            ${lib.optionalString cfg.role.controlPlane.enable ''
              controlPlane:
                certificateKey: "$CERTIFICATE_KEY"
            ''}
            EOF

            ${lib.optionalString (cfg.network.internal.interface != null) ''
              _interface_ip=$(fish-out-netif-ip ${cfg.network.internal.interface})

              echo "Using $_interface_ip as 'localAPIEndpoint.advertiseAddress', 'apiServer.certSANs', and 'nodeRegistration.kubeletExtraArgs[\"--node-ip\"]'"

              yq --inplace \
                 '   with(select(.kind == "JoinConfiguration");
                       .localAPIEndpoint.advertiseAddress = "'"$_interface_ip"'"
                     | .nodeRegistration.kubeletExtraArgs = [ { "name": "node-ip", "value": "'"$_interface_ip"'" } ])' \
                 "$_config"

              ${lib.optionalString cfg.role.controlPlane.enable ''
                yq --inplace \
                  '   with(select(.kind == "JoinConfiguration");
                        .controlPlane.localAPIEndpoint.advertiseAddress = "'"$_interface_ip"'")' \
                  "$_config"
              ''}
            ''}

            cat "$_config"
            kubeadm join --config "$_config"
            systemctl start --no-block kubernetes-full.target
          '';
        };

    systemd.services."kubeadm-init" = lib.mkIf cfg.role.controlPlane.enable {
      path = [
        config.services.kubernetes.package
        pkgs.util-linux
        pkgs.yq-go
        pkgs.jq
        pkgs.iproute2
        inputs."self".legacyPackages.${pkgs.stdenv.hostPlatform.system}.fish-out-netif-ip
      ];

      environment."KUBECONFIG" = "/etc/kubernetes/admin.conf";

      script = ''
        set -eEuo pipefail

        if [[ -f "/etc/kubernetes/.kubeadm-init-done" ]] ; then
          echo "Not re-running 'kubeadm init'"
          exit 0
        fi

        _config="/etc/kubernetes/kubeadm-config.yaml"
        cp ${kubeadmConfig} "$_config"

        ${lib.optionalString (cfg.network.internal.interface != null) ''
          _interface_ip=$(fish-out-netif-ip ${cfg.network.internal.interface})

          echo "Using $_interface_ip as 'localAPIEndpoint.advertiseAddress', 'apiServer.certSANs', and 'nodeRegistration.kubeletExtraArgs[\"--node-ip\"]'"

          yq --inplace \
             '   with(select(.kind == "InitConfiguration");
                   .localAPIEndpoint.advertiseAddress = "'"$_interface_ip"'"
                 | .nodeRegistration.kubeletExtraArgs = [ { "name": "node-ip", "value": "'"$_interface_ip"'" } ])
               | with(select(.kind == "ClusterConfiguration");
                   .apiServer.certSANs = .apiServer.certSANs + [ "'"$_interface_ip"'" ]
                 | .controlPlaneEndpoint = "'"$_interface_ip"':6443" )' \
             "$_config"
        ''}

        kubeadm init \
          --config "$_config" \
          --ignore-preflight-errors=all \
          --upload-certs

        _prev_csr_count=0
        while ! mapfile -d ' ' -t _csrs < <(kubectl get csr -o jsonpath='{.items[*].metadata.name}') || ! [[ "''${#_csrs[@]}" = "$_prev_csr_count" ]] ; do
          echo "waiting for CSR count to stabilize, had $_prev_csr_count, now we have ''${#_csrs[@]}, waiting 10 seconds"
          _prev_csr_count="''${#_csrs[@]}"
          sleep 10
        done
        echo "CSR count stabilized at ''${#_csrs[@]}"
        for _csr in "''${_csrs[@]}" ; do
          kubectl certificate approve "$_csr"
        done

        touch /etc/kubernetes/.kubeadm-init-done

        ${lib.optionalString cfg.role.worker.enable ''
          kubectl taint node ${config.networking.hostName} node-role.kubernetes.io/control-plane-
        ''}

        systemctl start --no-block kubernetes-full.target
      '';

      serviceConfig = {
        RuntimeDirectory = "kubeadm-init";
        Type = "oneshot";
        RemainAfterExit = "yes";
      };
    };
  };
}
