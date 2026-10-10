{ config, lib, ... }:
let
  cfg = config.skarnos.kubernetes.containerd;
in
{
  options.skarnos.kubernetes.containerd = {
    systemdCgroup = lib.mkEnableOption "the systemd cgroup driver in the default runtime";
    writableCgroups = lib.mkEnableOption ''
      a `cgroup-writable` runtime handler for use with a RuntimeClass.
      Pods using it need `hostUsers: false`
    '';
  };

  config = lib.mkIf config.skarnos.kubernetes.enable {
    virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".containerd.runtimes = {
      runc.options.SystemdCgroup = lib.mkIf cfg.systemdCgroup (lib.mkForce true);
      cgroup-writable = lib.mkIf cfg.writableCgroups {
        runtime_type = "io.containerd.runc.v2";
        cgroup_writable = true;
        options.SystemdCgroup = true;
      };
    };
  };
}
