{ perSystem, pkgs, ... }:
{
  networking.firewall.trustedInterfaces = [
    "enp7s0"
    "cni0"
  ];

  environment.systemPackages = [ pkgs.linkerd ];
  services.kubernetes.kubelet.hostname = "controller-1";
  skarnos.kubernetes = {
    enable = true;
    package = perSystem."skarnos"."kubernetes_1_33";
    clusterName = "skarnos";

    network = {
      podSubnet = "10.252.0.0/15";
      serviceSubnet = "10.254.0.0/16";
      internal.interface = "enp7s0";

      cni."flannel" = { };
    };

    role.controlPlane = {
      enable = true;

      hosts = [ "10.100.0.3" ];
    };
  };
}
