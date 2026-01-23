{
  testers,
  kubernetes,
}:
testers.runNixOSTest {
  name = "numtides-awesome-test";

  testScript = ''
    # this will wait for nodes to boot
    node1.wait_for_unit("default.target")
    node2.wait_for_unit("default.target")

    # do some imperative setup
    node1.succeed("kubeadm version")
  '';

  nodes = {
    node1 =
      { config, pkgs, ... }:
      {
        environment.systemPackages = [
          kubernetes
        ];
      };
    node2 =
      { config, pkgs, ... }:
      {
      };
  };
}
