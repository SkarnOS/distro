{
  lib,
  buildGoModule,
  fetchFromGitHub,
  which,
  makeWrapper,
  rsync,
  installShellFiles,
  runtimeShell,
  nixosTests,
  nix-update-script,
  jq,
  writers,
  breakpointHook,
  fetchpatch,

  version,
  hash,
  is_maintained,
  containers,
}:
let
  binariesFilter = ''
    .components | to_entries | map(.value.program) | join(" ")
  '';
  commandsFilter = ''
    .components | keys | join(" ")
  '';
  completionsFilter = ''
    to_entries
      | map(
        .value.program as $program
          | .value.completion // []
          | map("--\(.) <($out/bin/\($program) completion \(.))")
          | join("\n")
      ) | join("\n")
  '';
in
lib.fix (
  self:
  buildGoModule (finalAttrs: {
    pname = "kubernetes";
    inherit version;

    __structuredAttrs = true;

    src = fetchFromGitHub {
      owner = "kubernetes";
      repo = "kubernetes";
      tag = "v${finalAttrs.version}";
      inherit hash;
    };

    vendorHash = null;

    doCheck = false;

    nativeBuildInputs = [
      jq
      makeWrapper
      which
      rsync
      installShellFiles
      breakpointHook
    ];

    outputs = [
      "out"
      "man"
      "pause"
    ];

    patches = [
      (fetchpatch {
        url = "https://raw.githubusercontent.com/NixOS/nixpkgs/3ceaaa8bc963ced4d830e06ea2d0863b6490ff03/pkgs/by-name/ku/kubernetes/fixup-addonmanager-lib-path.patch";
        hash = "sha256-ivhwOK/SGtQQJ+MONeJo8yEsxb9q+DuzlZDYEIp6eA0=";
      })
    ];

    components = {
      "cmd/kubeadm" = {
        program = "kubeadm";
        completion = [
          "bash"
          "zsh"
          "fish"
        ];
      };
      "cmd/kubelet".program = "kubelet";
      "cmd/kube-apiserver".program = "kube-apiserver";
      "cmd/kube-controller-manager".program = "kube-controller-manager";
      "cmd/kube-proxy".program = "kube-proxy";
      "cmd/kube-scheduler".program = "kube-scheduler";
      "cmd/kubectl" = {
        program = "kubectl";
        completion = [
          "bash"
          "zsh"
          "fish"
        ];
      };
      "cmd/kubectl-convert".program = "kubectl-convert";
    };

    buildPhase = ''
      runHook preBuild

      substituteInPlace "hack/update-generated-docs.sh" --replace "make" "make SHELL=${runtimeShell}"
      patchShebangs ./hack ./cluster/addons/addon-manager

      _what="$(jq -r '${commandsFilter}' /build/.attrs.json)"

      make "SHELL=${runtimeShell}" "WHAT=$_what"
      ./hack/update-generated-docs.sh
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      _what="$(jq -r '${binariesFilter}' /build/.attrs.json)"

      for _binary in $_what; do
        install -D _output/local/go/bin/$_binary -t $out/bin
      done

      cc build/pause/linux/pause.c -o pause
      install -D pause -t $pause/bin

      rm docs/man/man1/kubectl*
      installManPage docs/man/man1/*.[1-9]

      # Unfortunately, kube-addons-main.sh only looks for the lib file in either the
      # current working dir or in /opt. We have to patch this for now.
      substitute cluster/addons/addon-manager/kube-addons-main.sh $out/bin/kube-addons \
        --subst-var out

      chmod +x $out/bin/kube-addons
      wrapProgram $out/bin/kube-addons --set "KUBECTL_BIN" "$out/bin/kubectl"

      cp cluster/addons/addon-manager/kube-addons.sh $out/bin/kube-addons-lib.sh

      readarray -t _completions < <(jq -r '${completionsFilter}' "/build/.attrs.json")

      installShellCompletion --cmd kubeadm "''${_completions[@]}"
      runHook postInstall
    '';

    passthru = {
      inherit is_maintained containers;
    };

    meta = {
      description = "Production-Grade Container Scheduling and Management";
      license = lib.licenses.asl20;
      homepage = "https://kubernetes.io";
      teams = [ lib.teams.kubernetes ];
      platforms = lib.platforms.linux;
    };
  })
)
