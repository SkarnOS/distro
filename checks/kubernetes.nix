{
  testers,
  dockerTools,
  cilium-cli,
  containerd,
  lib,
  writers,

  kubernetes,
  inputs,
}:
let
  ciliumParams = {
    "bpf.masquerade" = "true";
    "ipv6.enabled" = "true";
    "ipam.mode" = "kubernetes";
    "bpf.lbExternalClusterIP" = "true";
    "envoy.enabled" = "false";
    "encryption.enabled" = "true";
    "encryption.type" = "wireguard";
    "k8sServiceHost" = "127.0.0.1";
    "image.useDigest" = "false";
    "certgen.useDigest" = "false";
    "hubble.relay.image.useDigest" = "false";
    "hubble.ui.backend.useDigest" = "false";
    "hubble.ui.frontend.useDigest" = "false";
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
  };
in
testers.nixosTest {
  name = "nix-kubernetes";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [
        inputs.self.nixosModules."kubernetes"
      ];

      systemd.network.enable = true;
      networking.useNetworkd = true;

      virtualisation = {
        cores = 2;
        memorySize = 4096;
        diskSize = 1024 * 20;
        # restrictNetwork = true;
      };

      services.kubernetes.package = kubernetes;

      services.resolved.settings.Resolve = {
        DNSStubListenerExtra = "10.224.6.236";
      };

      networking.firewall.enable = false;

      rename-me.kubernetes = {
        enable = true;
        network = {
          cni."cilium" = { };
          ingress.interface = "eth0";
          nameservers = [ "10.224.6.236" ];
        };
        clusterName = "test-cluster";
      };

      system.stateVersion = "25.11";
    };

  testScript = ''
    import json
    from pathlib import Path
    from functools import reduce
    import operator

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

    machine.wait_for_unit("multi-user.target")
    ${lib.concatMapStringsSep "\n" (
      { name, value }:
      lib.concatMapStringsSep "\n" (value: ''
        machine.succeed("${lib.getExe' containerd "ctr"} -n k8s.io image import ${value}")
      '') value
    ) (lib.mapAttrsToList lib.nameValuePair kubernetes.passthru.containers)}

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
      "--version", "1.18.2",
      *cilium_params
    ]))

    print(machine.succeed("cilium status --wait"))
    print(machine.succeed("cilium connectivity test"))


  '';
}
