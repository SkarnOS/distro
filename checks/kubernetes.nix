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
    "operator.image.useDigest" = "false";
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

      environment.systemPackages = [
        cilium-cli
      ];

      systemd.network.enable = true;
      networking.useNetworkd = true;

      virtualisation = {
        cores = 2;
        memorySize = 4096;
        diskSize = 4096;
      };

      rename-me.kubernetes = {
        enable = true;
        network = {
          cni."cilium" = { };
          ingress.interface = "eth0";
        };
        clusterName = "machine";

      };

      system.stateVersion = "25.11";
    };

  testScript = ''
    import json
    from pathlib import Path
    from functools import reduce
    import operator

    machine.wait_for_unit("multi-user.target")
    ${lib.concatMapStringsSep "\n" (
      { name, value }:
      let
        namespace = lib.traceVal (if lib.hasPrefix "quay.io" name then "k8s.io" else "k8s.io");
      in
      ''
        machine.succeed("${lib.getExe' containerd "ctr"} -n ${namespace} image import ${value}")
      ''
    ) (lib.mapAttrsToList lib.nameValuePair kubernetes.passthru.containers)}

    cilium_params: list[str] = reduce(
      operator.add,
      map(
        lambda param: ["--set", f"{param[0]}={param[1]}"],
        json.loads(Path("${writers.writeJSON "cilium-params.json" ciliumParams}").read_text()).items()
      )
    )

    machine.succeed("kubeadm init --config /etc/kubernetes/kubeadm-cp-init.yaml --ignore-preflight-errors=all --upload-certs")
    machine.succeed(" ".join([
      "cilium",
      "install",
      "--version", "1.18.2",
      *cilium_params
    ]))
    print(machine.succeed("kubectl get nodes"))
  '';
}
