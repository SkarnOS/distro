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
  sshBackdoor = {
    _file = ./kubernetes.nix;
    users.users.root.hashedPassword = "";
    services.openssh.settings.PermitRootLogin = "yes";
    services.openssh.settings.PermitEmptyPasswords = "yes";
    security.pam.services.sshd.allowNullPassword = true;
  };

  common = {
    _file = ./kubernetes.nix;

    systemd.network.enable = true;
    networking.useNetworkd = true;

    virtualisation = {
      cores = 4;
      memorySize = 4096;
      diskSize = 1024 * 20;
      restrictNetwork = true;

      networking.firewall.enable = false;

      systemd.network.networks."09-vmlink" = {
        matchConfig.Name = "eth1";
        networkConfig.Address =
          nodes.${config.virtualisation.test.nodeName}.networking.primaryIPAddress + "/24";
      };

      services.openssh = {
        enable = true;
        permitRootLogin = "yes";
      };

      skarnos.kubernetes.package = lib.mkForce kubernetes;

      system.stateVersion = "25.11";
    };

    networking.firewall.enable = false;

    services.openssh = {
      enable = true;
      permitRootLogin = "yes";
    };

    system.stateVersion = "25.11";
  };
in
testers.nixosTest {
  name = "nix-kubernetes";

  nodes = {
    controller-1 =
      { pkgs, nodes, ... }:
      {
        imports = [
          inputs.self.nixosModules."kubernetes"
          sshBackdoor
          common
        ];

        skarnos.kubernetes = {
          enable = true;
          package = kubernetes;
          clusterName = "test-cluster";
          sshTarget = "controller-1";

          network = {
            podSubnet = "10.252.0.0/15";
            serviceSubnet = "10.254.0.0/16";
            internal.interface = "eth0";

            cni."flannel" = {
              settings.network.IPv6Network = "fd08:4e1:1::/52";
            };
          };

          role.controlPlane = {
            enable = true;

            hosts = [ "10.0.2.15" ];
          };
        };
      };
  };

  testScript = ''
    start_all()
    controller_1.succeed("ip route add default via 10.0.2.1");
    controller_1.wait_for_unit("kubernetes-full.target")

    def is_coredns_running(timeout):
      status, coredns_unavailable_replicas = \
        controller_1.execute("kubectl -n kube-system get deployment coredns -o jsonpath='{.status.readyReplicas}'")

      if status != 0:
        return False
      else:
        try:
          return int(coredns_unavailable_replicas.strip()) == 2
        except ValueError:
          return False

    retry(is_coredns_running)
  '';
}
