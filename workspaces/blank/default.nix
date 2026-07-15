{ pkgs, workspaces, utils }:

{
  workspaces."blank" = {
    workspace.file."hello.txt" = ''
      Hello, world!
    '';
  };
}
