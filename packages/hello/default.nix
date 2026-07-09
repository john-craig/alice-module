# packages/hello/default.nix
#
# Sample package — a minimal shell script that prints "Hello, world!".
# Use this as a starting point for adding real packages to the flake.
{ pkgs }:

pkgs.writeShellApplication {
  name = "hello";
  text = ''
    echo "Hello, world!"
  '';
}
