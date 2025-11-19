{ pkgs ? import <nixpkgs> {} }:
let
  used_stdenv = pkgs.stdenv;
in
used_stdenv.mkDerivation {
  name = "build-environment";
  buildInputs = with pkgs;
    [
      gnuplot
      (texliveBasic.withPackages (ps: with ps; [mathtools enumitem]))
    ];
}
