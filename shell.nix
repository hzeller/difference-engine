{ pkgs ? import <nixpkgs> {} }:
let
  used_stdenv = pkgs.stdenv;
#  used_stdenv = pkgs.clangStdenv;
in
used_stdenv.mkDerivation {
  name = "build-environment";
  buildInputs = with pkgs;
    [
      gnuplot
      rustc

      llvmPackages_21.clang-tools  # clangd
    ];
}
