{
  description = "lisp: SLY's debugger, frames and compile-a-form for coding agents, as a command";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/4382ed2b7a6839d4280a9b386db49cbc5907414d";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The directory with slynk.asd in nixpkgs' SLY.
      slynkDirectory = pkgs: "${pkgs.sbclPackages.slynk}/slynk/";

      lisp = pkgs: pkgs.stdenvNoCC.mkDerivation {
        pname = "slynk-cli";
        version = "0.1.0";
        src = ./.;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/share/slynk-cli $out/bin
          cp -r src docs $out/share/slynk-cli/
          # The command runs on this SBCL; the image runs the project's.
          makeWrapper ${pkgs.sbcl}/bin/sbcl $out/bin/lisp \
            --add-flags "--script $out/share/slynk-cli/src/client.lisp" \
            --set-default SLYNK_CLI_SLYNK ${slynkDirectory pkgs}
        '';
        meta.mainProgram = "lisp";
      };

      # The SBCL of the benchmark: what the tasks need, never a library a
      # task puts a defect into (bench/README.md).
      benchLisp = pkgs: pkgs.sbcl.withPackages (ps: with ps; [
        alexandria fiasco fiveam flexi-streams
        # fset-bug: FSet's dependencies; its tests are in FSet itself.
        misc-extensions mt19937 named-readtables
        # jzon-bug: jzon's dependencies; its tests use fiveam and alexandria.
        closer-mop float-features trivial-gray-streams
      ]);
    in
    {
      packages = forAllSystems (pkgs: { default = lisp pkgs; });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.sbcl pkgs.git ];
          SLYNK_CLI_SLYNK = slynkDirectory pkgs;
        };
        bench = pkgs.mkShell {
          packages = [ (benchLisp pkgs) pkgs.git pkgs.jq pkgs.util-linux ];
          SLYNK_CLI_SLYNK = slynkDirectory pkgs;
          BENCH_LISP = lisp pkgs;
          BENCH_SRC_CL_PPCRE = pkgs.sbclPackages.cl-ppcre.src;
          BENCH_SRC_LOCAL_TIME = pkgs.sbclPackages.local-time.src;
          BENCH_SRC_FSET = pkgs.sbclPackages.fset.src;
          BENCH_SRC_JZON = pkgs.sbclPackages.com_dot_inuoe_dot_jzon.src;
        };
      });

      checks = forAllSystems (pkgs: {
        test = pkgs.runCommand "slynk-cli-test" {
          nativeBuildInputs = [ pkgs.sbcl pkgs.git pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
          SLYNK_CLI_SLYNK = slynkDirectory pkgs;
        } ''
          export HOME=$TMPDIR
          cp -r ${./.} src && chmod -R u+w src && cd src
          patchShebangs bin test
          bash test/run.sh
          touch $out
        '';
      });
    };
}
