{ writeShellApplication, openssl }:
writeShellApplication {
  name = "skarnos";

  text = builtins.readFile ./main.sh;

  runtimeInputs = [
    openssl
  ];
}
