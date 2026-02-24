{
  cilium-cli,
  fetchFromGitHub,
}:
let
  version = "0.19.1";
in
cilium-cli.overrideAttrs (
  _: prevAttrs: {
    inherit version;

    src = fetchFromGitHub {
      owner = "cilium";
      repo = "cilium-cli";
      tag = "v${version}";
      hash = "sha256-ZxXFd6ZGptGIixQZyavufb9RlmyHlte5GCQZ1wlKSFA=";
    };

    postPatch = ''
      sed -E --in-place \
        --expr 's~(quay.io/cilium/network-perf:[^@]+)@sha256:[^"]+~\1~' \
        --expr 's~(quay.io/cilium/alpine-curl:[^@]+)@sha256:[^"]+~\1~' \
        --expr 's~(quay.io/cilium/json-mock:[^@]+)@sha256:[^"]+~\1~' \
        --expr 's~(registry.k8s.io/coredns/coredns:[^@]+)@sha256:[^"]+~\1~' \
        --expr 's~(quay.io/cilium/test-connection-disruption:[^@]+)@sha256:[^"]+~\1~' \
        --expr 's~(quay.io/frrouting/frr:[^@]+)@sha256:[^"]+~\1~' \
        --expr 's~(docker.io/alpine/socat:[^@]+)@sha256:[^"]+~\1~' \
        vendor/github.com/cilium/cilium/cilium-cli/defaults/defaults.go
      cat vendor/github.com/cilium/cilium/cilium-cli/defaults/defaults.go | grep -qv '@sha256'
    '';
  }
)
