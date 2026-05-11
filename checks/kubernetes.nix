{
  testers,
  dockerTools,
  cilium-cli,
  containerd,
  parallel,
  lib,
  writers,
  openssh,
  iputils,
  stdenv,

  kubernetes,
  inputs,
}:
let
  common =
    { config, nodes, ... }:
    {
      _file = ./kubernetes.nix;
      _module.args.hostName = config.virtualisation.test.nodeName;

      users.users.root.hashedPassword = "";
      services.openssh.settings.PermitRootLogin = "yes";
      services.openssh.settings.PermitEmptyPasswords = "yes";
      security.pam.services.sshd.allowNullPassword = true;

      systemd.network.enable = true;
      networking.useNetworkd = true;

      virtualisation = {
        cores = 4;
        memorySize = 4096;
        diskSize = 1024 * 20;
      };

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
in
testers.runNixOSTest (
  { nodes, ... }:
  {
    name = "nix-kubernetes";

    node = {
      specialArgs = {
        inherit (inputs.example) inputs;
        perSystem = lib.mapAttrs (
          _: attrs: attrs.packages.${stdenv.hostPlatform.system}
        ) inputs.example.inputs;
      };
      pkgsReadOnly = false;
    };

    nodes = {
      controller-1 =
        { pkgs, nodes, ... }:
        {
          imports = [
            common
            "${inputs.example}/hosts/controller-1/configuration.nix"
          ];

          skarnos.kubernetes = {
            sshTarget = "controller-1";

            network = {
              podSubnet = "10.252.0.0/15";
              serviceSubnet = "10.254.0.0/16";
              internal.interface = lib.mkForce "eth1";

              cni."flannel" = {
                settings.network.IPv6Network = "fd08:4e1:1::/52";
              };
            };

            role.controlPlane.hosts = [ "10.0.2.15" ];
          };

          virtualisation = {
            forwardPorts = [
              {
                from = "host";
                host.port = 2221;
                guest.port = 22;
              }
            ];
          };
        };

      worker-1 =
        { pkgs, nodes, ... }:
        {
          imports = [
            common
            "${inputs.example}/hosts/worker-1/configuration.nix"
          ];

          skarnos.kubernetes = {
            sshTarget = "worker-1";

            network = {
              podSubnet = "10.252.0.0/15";
              serviceSubnet = "10.254.0.0/16";
              internal.interface = lib.mkForce "eth1";

              cni."flannel" = {
                settings.network.IPv6Network = "fd08:4e1:1::/52";
              };
            };
          };

          virtualisation = {
            forwardPorts = [
              {
                from = "host";
                host.port = 2222;
                guest.port = 22;
              }
            ];
          };
        };
    };

    testScript = ''
      import subprocess
      import os

      os.environ["PATH"] = os.environ["PATH"] + ":${openssh}/bin:${iputils}/bin"
      os.environ["NIX_SSHOPTS"] = "-oStrictHostKeyChecking=no"

      fish_out_netif_ip_command = "${
        lib.getExe inputs."self".legacyPackages.${stdenv.hostPlatform.system}.fish-out-netif-ip
      }"
      skarnos_command = "${lib.getExe inputs."self".legacyPackages.${stdenv.hostPlatform.system}.skarnos}"

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

      def are_all_nodes_ready(timeout):
        status, coredns_unavailable_replicas = \
          controller_1.execute("kubectl get nodes -o 'jsonpath={.items[*].status.conditions}' | jq --slurp --exit-status --raw-output '[. | flatten | .[] | select(.type == \"Ready\")] | all(.status == \"True\")'")

        if status != 0:
          return False
        else:
          return True

      controller_1.start()
      controller_1.wait_for_unit("sshd.service")

      worker_1.start()
      worker_1.wait_for_unit("sshd.service")

      controller_1.execute("systemctl start kubeadm-init.service")
      controller_1.wait_for_unit("kubernetes-full.target")

      retry(is_coredns_running)

      process = subprocess.run(f"{skarnos_command} join --interface eth1 --address ssh://root@localhost:2221 ssh://root@localhost:2222", shell=True)
      assert process.returncode == 0, f"`skarnos join`: exited with exit code {process.returncode}"

      worker_1.wait_for_unit("kubernetes-full.target")

      retry(are_all_nodes_ready)

    '';
  }
)
