{ pkgs ? import <nixpkgs> {} }:
let
  used_stdenv = pkgs.stdenv;
  #  used_stdenv = pkgs.clangStdenv;
  xls = pkgs.stdenv.mkDerivation rec {
    name = "xls";
    version = "v0.0.0-10596-g83b1ffcde";
    src = pkgs.fetchurl {
      url = "https://github.com/google/xls/releases/download/${version}/xls-${version}-linux-x64.tar.gz";
      hash = "sha256-kN5cpElunEICzdOr1Fp/xqZT5NsPtfmenb8PIAuTHxU=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
        mkdir -p $out/bin

        # The XLS names are very non-descript, and use underscores.
        # Give them some proper names.
        for f in *_main ; do
           mv $f $out/bin/$(echo xls-$f | sed 's/_main//' | sed 's/_/-/g');
        done

        # dslx binaries don't have the main-suffix anymore, but still
        # punchcard-era underscores.
        mv dslx_ls $out/bin/dslx-ls
        mv dslx_fmt $out/bin/dslx-fmt

        # xls standard library
        mkdir -p $out/lib/xls
        mv xls/dslx $out/lib/xls
    '';
  };
in
used_stdenv.mkDerivation {
  name = "build-environment";
  buildInputs = with pkgs;
    [
      gnuplot
      rustc
      xls

      llvmPackages_21.clang-tools  # clangd
    ];
}
