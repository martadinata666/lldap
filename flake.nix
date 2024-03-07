{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    naersk.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.inputs.flake-utils.follows = "utils";
    cross-naersk.url = "github:icewind1991/cross-naersk";
    cross-naersk.inputs.nixpkgs.follows = "nixpkgs";
    cross-naersk.inputs.naersk.follows = "naersk";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    naersk,
    rust-overlay,
    cross-naersk,
  }:
    utils.lib.eachDefaultSystem (system: let
      overlays = [(import rust-overlay)];
      pkgs = import nixpkgs {
        inherit system overlays;
      };
      lib = pkgs.lib;

      hostTarget = pkgs.hostPlatform.config;
      targets = [
        "x86_64-unknown-linux-musl"
        "i686-unknown-linux-musl"
        "armv7-unknown-linux-musleabihf"
        "aarch64-unknown-linux-musl"
        "x86_64-unknown-freebsd"
      ];
      clientTargets = [
        "x86_64-unknown-linux-musl"
        "i686-unknown-linux-musl"
        "armv7-unknown-linux-musleabihf"
        "aarch64-unknown-linux-musl"
        "x86_64-unknown-freebsd"
        "x86_64-pc-windows-gnu"
      ];

      inherit (builtins) listToAttrs fromTOML readFile;
      inherit (lib.attrsets) genAttrs nameValuePair;
      inherit (lib.lists) map;
      inherit (cross-naersk') execSufficForTarget;

      artifactForTarget = target: "lldap";
      assetNameForTarget = target: "lldap-${target}";

      cross-naersk' = pkgs.callPackage cross-naersk {
        inherit naersk;
        toolchain = pkgs.rust-bin.stable.latest.default;
      };

      src = lib.sources.sourceByRegex (lib.cleanSource ./.) ["Cargo.*" "(src|tests|test_client|build.rs|appinfo)(/.*)?"];

      nearskOpt = {
        pname = "lldap";
        inherit src;
        cargoBuildOptions = x: x++ ["-p" "lldap_set_password" "-p" "lldap_migration_tool"];
      };
      buildServer = target: (cross-naersk'.buildPackage target) nearskOpt;
      hostNaersk = cross-naersk'.hostNaersk;

      checks = ["check" "clippy" "test"];

      msrv = (fromTOML (readFile ./Cargo.toml)).package.rust-version;
      msrvToolchain = pkgs.rust-bin.stable."${msrv}".default;
      naerskMsrv = let
        toolchain = msrvToolchain;
      in
        pkgs.callPackage naersk {
          cargo = toolchain;
          rustc = toolchain;
        };

      testClientArtifactForTarget = target: "test_client${execSufficForTarget target}";

    in rec {
      # `nix build`
      packages =
        # cross compile lldap for all targets
        (genAttrs targets buildServer) //
        # check,test,clippy for lldap
        (genAttrs checks (mode: hostNaersk.buildPackage (nearskOpt // { inherit mode;}))) //
        // rec {
          lldap = hostNaersk.buildPackage nearskOpt;
          checkMsrv = naerskMsrv.buildPackage (nearskOpt
            // {
              mode = "check";
            });
          default = lldap;
        };


      devShells = {
	    default = cross-naersk'.mkShell targets {
          nativeBuildInputs = with pkgs; [
            (rust-bin.beta.latest.default.override {targets = targets ++ [hostTarget];})
            krankerl
            cargo-edit
            cargo-outdated
            cargo-audit
          ];
        };
	    msrv = cross-naersk'.mkShell targets {
          nativeBuildInputs = with pkgs; [
            msrvToolchain
          ];
        };
      };
    });
}
