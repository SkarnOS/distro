{
  testers,
  dockerTools,
  cilium-cli,
  containerd,

  kubernetes,
  inputs,
}:
let
  corednsPod = dockerTools.pullImage {
    imageName = "registry.k8s.io/coredns/coredns";
    imageDigest = "sha256:e8c262566636e6bc340ece6473b0eed193cad045384401529721ddbe6463d31c";
    hash = "sha256-8Op3vzupnC6kWIgjqk4ck2tzY2sra+L3xdzoQ4TTUtI=";
    finalImageName = "registry.k8s.io/coredns/coredns";
    finalImageTag = "v1.12.1";
  };
  pausePod = dockerTools.pullImage {
    imageName = "registry.k8s.io/pause";
    imageDigest = "sha256:278fb9dbcca9518083ad1e11276933a2e96f23de604a3a08cc3c80002767d24c";
    hash = "sha256-okwwg3Tclhh/BlzSA2BBIpT261HH2zXgEi0Z+PMTtnQ=";
    finalImageName = "registry.k8s.io/pause";
    finalImageTag = "3.10.1";
  };
  etcdPod = dockerTools.pullImage {
    imageName = "registry.k8s.io/etcd";
    imageDigest = "sha256:042ef9c02799eb9303abf1aa99b09f09d94b8ee3ba0c2dd3f42dc4e1d3dce534";
    hash = "sha256-1RpUGmoHzEv8IVGxQ7yEPxKRpRgRlpgJWyj5hrS8p3o=";
    finalImageName = "registry.k8s.io/etcd";
    finalImageTag = "3.6.5-0";
  };
  kubeapiPod = dockerTools.pullImage {
    imageName = "registry.k8s.io/kube-apiserver";
    imageDigest = "sha256:5af1030676ceca025742ef5e73a504d11b59be0e5551cdb8c9cf0d3c1231b460";
    hash = "sha256-xw2jlxwwrrCx6p4/tFJMRKOwPknFrSA3Cws1+Ij8gfc=";
    finalImageName = "registry.k8s.io/kube-apiserver";
    finalImageTag = "v1.34.3";
  };
  kubeschedulerPod = dockerTools.pullImage {
    imageName = "registry.k8s.io/kube-scheduler";
    imageDigest = "sha256:f9a9bc7948fd804ef02255fe82ac2e85d2a66534bae2fe1348c14849260a1fe2";
    hash = "sha256-TNZoxx+rDvQIMdMVYjxLezOyTpoW7ZAfplwCwAR/PqI=";
    finalImageName = "registry.k8s.io/kube-scheduler";
    finalImageTag = "v1.34.3";
  };
  kubecontrollerPod = dockerTools.pullImage {
    imageName = "registry.k8s.io/kube-controller-manager";
    imageDigest = "sha256:716a210d31ee5e27053ea0e1a3a3deb4910791a85ba4b1120410b5a4cbcf1954";
    hash = "sha256-GMaP/nwNEpvUEydKuZ5DnK0hQLAUsd9BKwmcHktNdl8=";
    finalImageName = "registry.k8s.io/kube-controller-manager";
    finalImageTag = "v1.34.3";
  };
  ciliumPod = dockerTools.pullImage {
    imageName = "quay.io/cilium/cilium";
    imageDigest = "sha256:858f807ea4e20e85e3ea3240a762e1f4b29f1cb5bbd0463b8aa77e7b097c0667";
    hash = "sha256-ceTrgHYFk0nAhGRdZEkmEPgbTx8gO4DG6X+OySNbDC4=";
    finalImageName = "quay.io/cilium/cilium";
    finalImageTag = "v1.18.2";
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

      helsinki.kubernetes = {
        enable = true;
        network = {
          cni = "cilium";
          ingress.interface = "eth0";
        };
        clusterName = "machine";

      };

      system.stateVersion = "25.11";
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("${containerd}/bin/ctr -n k8s.io image import ${pausePod}")
    machine.succeed("${containerd}/bin/ctr -n k8s.io image import ${corednsPod}")
    machine.succeed("${containerd}/bin/ctr -n k8s.io image import ${etcdPod}")
    machine.succeed("${containerd}/bin/ctr -n k8s.io image import ${kubeapiPod}")
    machine.succeed("${containerd}/bin/ctr -n k8s.io image import ${kubecontrollerPod}")
    machine.succeed("${containerd}/bin/ctr -n k8s.io image import ${kubeschedulerPod}")
    machine.succeed("${containerd}/bin/ctr -n quay.io image import ${ciliumPod}")
    machine.succeed("kubeadm init --config /etc/kubernetes/kubeadm-cp-init.yaml --ignore-preflight-errors=all --upload-certs")
    machine.succeed("cilium install --set bpf.masquerade=true --set ipv6.enabled=true --set ipam.mode=kubernetes --set bpf.lbExternalClusterIP=true --set envoy.enabled=false --version 1.18.2 --set encryption.enabled=true --set encryption.type=wireguard --set k8sServiceHost=127.0.0.1")
    print(machine.succeed("kubectl get nodes"))
  '';
}
