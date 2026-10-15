{
  description = "Haskell AMO metadata fetcher with Cabal tests and Haddock documentation";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      perSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = { };
            overlays = [ ];
          };
          source = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./src
              ./app
              ./test
              ./docs
              ./firefox-addon-fetcher.cabal
              ./cabal.project
              ./LICENSE
              ./README.md
              ./CHANGELOG.md
              ./CONTRIBUTING.md
              ./fourmolu.yaml
              ./.editorconfig
              ./flake.nix
              ./flake.lock
            ];
          };
          # Cabal is the single declaration of Haskell component dependencies.
          package =
            (pkgs.haskell.lib.overrideCabal
              (pkgs.haskellPackages.callCabal2nix "firefox-addon-fetcher" source { })
              (old: {
                configureFlags = (old.configureFlags or [ ]) ++ [ "-fstrict" ];
                doCheck = true;
                doHaddock = true;
              })
            ).overrideAttrs
              (old: {
                meta = (old.meta or { }) // {
                  mainProgram = "addon-fetcher";
                };
              });
        in
        {
          inherit pkgs package;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          p = perSystem system;
        in
        {
          default = p.package;
        }
      );
      checks = forAllSystems (
        system:
        let
          p = perSystem system;
        in
        {
          tests = p.package;
        }
      );
      devShells = forAllSystems (
        system:
        let
          p = perSystem system;
        in
        {
          default = p.pkgs.haskellPackages.shellFor {
            packages = _: [ p.package ];
            nativeBuildInputs = [
              p.pkgs.cabal-install
              p.pkgs.fourmolu
              p.pkgs.nixfmt
            ];
          };
        }
      );
      formatter = forAllSystems (system: (perSystem system).pkgs.nixfmt-tree);
    };
}
