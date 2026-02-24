{
  testers,
  dockerTools,
  cilium-cli,
  containerd,
  parallel,
  lib,
  writers,

  kubernetes,
  inputs,
}:
let
  localRouterIpv4 = "10.224.6.1";
  ipv4NativeRoutingCIDR = "10.100.0.0/16";
  ciliumParams = {
    "bpf.masquerade" = "true";
    # "ipv6.enabled" = "true"; # no need for now
    "ipam.mode" = "kubernetes";
    "bpf.lbExternalClusterIP" = "true";
    "envoy.enabled" = "false";
    "encryption.enabled" = "true";
    "encryption.type" = "wireguard";
    "k8sServiceHost" = "127.0.0.1";
    "image.useDigest" = "false";
    "certgen.useDigest" = "false";
    "hubble.relay.image.useDigest" = "false";
    "hubble.ui.enabled" = "true";
    "hubble.relay.enabled" = "true";
    "hubble.ui.backend.image.useDigest" = "false";
    "hubble.ui.frontend.image.useDigest" = "false";
    "envoy.image.useDigest" = "false";
    "operator.image.useDigest" = "false";
    "nodeinit.image.useDigest" = "false";
    "preflight.image.useDigest" = "false";
    "preflight.envoy.image.useDigest" = "false";
    "clustermesh.apiserver.image.useDigest" = "false";
    "authentication.mutual.spire.install.initImage.useDigest" = "false";
    "authentication.mutual.spire.install.agent.image.useDigest" = "false";
    "authentication.mutual.spire.install.server.image.useDigest" = "false";
    "standaloneDnsProxy.image.useDigest" = "false";
    # added so i can hardcode the address
    "extraArgs[0]" = "--local-router-ipv4=${localRouterIpv4}";
    "routingMode" = "native";
    "endpointRoutes.enabled" = "true";
    "debug.enabled" = "true";
    inherit ipv4NativeRoutingCIDR;
  };

  containerImages = writers.writeText "container-images" (
    lib.concatMapStringsSep "\n" ({ name, value }: lib.concatStringsSep "\n" value) (
      lib.mapAttrsToList lib.nameValuePair kubernetes.passthru.containers
    )
  );

  sshBackdoor = {
    users.users.root.hashedPassword = "";
    services.openssh.settings.PermitRootLogin = "yes";
    services.openssh.settings.PermitEmptyPasswords = "yes";
    security.pam.services.sshd.allowNullPassword = true;
  };
in
testers.nixosTest {
  name = "nix-kubernetes";

  nodes = {
    httpServer =
      { pkgs, ... }:
      {
        imports = [
          sshBackdoor
        ];

        systemd.network.enable = true;
        networking.useNetworkd = true;

        networking.firewall.enable = false;

        systemd.services.nginx-certs = {
          before = [ "nginx.service" ];
          requiredBy = [ "nginx.service" ];

          path = [
            pkgs.openssl
          ];

          script = ''
            mkdir -p /var/lib/nginx
            openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 -days 365 -nodes \
              -keyout /var/lib/nginx/cert.key -out /var/lib/nginx/cert.crt \
              -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:one.one.one.one,DNS:k8s.io"
            chown nginx:nginx /var/lib/nginx/{cert.crt,cert.key}
          '';
        };

        services.nginx = {
          enable = true;

          appendHttpConfig = ''
            error_log stderr;
            access_log syslog:server=unix:/dev/log combined;
          '';

          virtualHosts."k8s.io" = {
            addSSL = true;
            sslCertificate = "/var/lib/nginx/cert.crt";
            sslCertificateKey = "/var/lib/nginx/cert.key";
          };

          virtualHosts."one.one.one.one" = {
            addSSL = true;
            sslCertificate = "/var/lib/nginx/cert.crt";
            sslCertificateKey = "/var/lib/nginx/cert.key";
          };
        };
      };
    machine =
      { pkgs, nodes, ... }:
      {
        imports = [
          inputs.self.nixosModules."kubernetes"
          sshBackdoor
        ];

        systemd.network.enable = true;
        networking.useNetworkd = true;

        virtualisation = {
          cores = 4;
          memorySize = 4096;
          diskSize = 1024 * 20;
          restrictNetwork = true;
          forwardPorts = [
            {
              from = "host";
              host.port = 2222;
              guest.port = 22;
            }
            {
              from = "host";
              host.port = 4245;
              guest.port = 4245;
            }
          ];
        };

        networking.hosts = {
          "${nodes.httpServer.networking.primaryIPAddress}" = [
            "one.one.one.one"
            "k8s.io"
          ];
        };

        services.resolved.settings.Resolve = {
          DNS = "";
          FallbackDNS = "";
        };

        services.kubernetes.package = kubernetes;

        services.resolved.settings.Resolve = {
          DNSStubListenerExtra = localRouterIpv4;
        };

        networking.firewall.enable = false;

        rename-me.kubernetes = {
          enable = true;
          network = {
            cni."cilium" = { };
            ingress.interface = "eth0";
            nameservers = [ localRouterIpv4 ];
          };
          clusterName = "test-cluster";
        };

        services.openssh = {
          enable = true;
          permitRootLogin = "yes";
        };

        system.stateVersion = "25.11";
      };
  };

  testScript = ''
    import json
    from pathlib import Path
    from functools import reduce
    import operator
    import ipaddress

    def approve_certificates(last):
      csrs = machine.succeed("kubectl get csr -o jsonpath='{.items[*].metadata.name}'").split(" ")
      print(csrs)
      if len(csrs) < 3:
        return False
      machine.succeed(f"kubectl certificate approve {' '.join(csrs)}")
      return True

    def wait_for_ready(last):
      nodes = machine.succeed("kubectl get nodes")
      return "NotReady" in nodes

    def get_ip_address(machine):
      address, prefix = next(
          (address["local"], str(address["prefixlen"])) for address in reduce(
            operator.add,
            (interface["addr_info"] for interface in json.loads(httpServer.succeed("ip --json addr"))
              if interface["ifname"] == "eth1"),
            [])
            if address["family"] == "inet"
        )

      ipv4_address = ipaddress.IPv4Address(address)
      ipv4_network = ipaddress.IPv4Network(address + "/" + prefix, strict = False)

      return ipv4_address, ipv4_network

    machine.wait_for_unit("multi-user.target")
    httpServer.wait_for_unit("nginx.service")

    machine.succeed("${lib.getExe parallel} -- ${lib.getExe' containerd "ctr"} -n k8s.io image import < ${containerImages}")

    cilium_params: list[str] = reduce(
      operator.add,
      map(
        lambda param: ["--set", f"{param[0]}={param[1]}"],
        json.loads(Path("${writers.writeJSON "cilium-params.json" ciliumParams}").read_text()).items()
      )
    )

    machine.succeed("kubeadm init --config /etc/kubernetes/kubeadm-cp-init.yaml --ignore-preflight-errors=all --upload-certs")

    retry(approve_certificates)

    retry(wait_for_ready)

    machine.succeed("kubectl taint nodes --all node-role.kubernetes.io/control-plane-")

    machine.succeed(" ".join([
      "cilium",
      "install",
      "--version", "${kubernetes.passthru.cilium_image_version}",
      *cilium_params
    ]))

    machine.succeed("cilium status --wait")
    machine.succeed("cilium hubble enable --ui")

    httpServer_address, httpServer_network = get_ip_address(httpServer)
    machine_address, machine_network = get_ip_address(machine)

    httpServer_other_address = httpServer_address + 29
    assert httpServer_other_address != machine_address
    assert httpServer_other_address in httpServer_network
    assert httpServer_network == machine_network

    machine.succeed("cilium hubble port-forward >/dev/console &")

    machine.execute(" ".join([
      "cilium connectivity test",
      "--single-node",
      "--external-cidr", str(httpServer_network),
      "--external-ip", str(httpServer_address),
      "--external-other-ip", str(httpServer_other_address),
      "--curl-insecure",
      "--debug", "--verbose",
      "--pause-on-fail",
      "--hubble", "--flow-validation warning",
      "--test tls-intercept", "--test to-service"
    ]))
  '';
}
