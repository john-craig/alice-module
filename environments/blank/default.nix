{ pkgs, envs, utils }:

{
  envs."blank" = {
    environment.file."hello.txt" = ''
      Hello, world!
    '';
  };
}
