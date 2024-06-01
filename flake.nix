{
  description = "A Flake for Mickael Kerjean's Filestash";
  nixConfig = {
    extra-substituters = [ "https://rrvw.cachix.org" ];
    extra-trusted-public-keys = [ "rrvw.cachix.org-1:caBqslbvcjJFC/n1hphsTZOQZScQLeF3DA5ukytHR4U=" ];
  };
  inputs = {
    filestash-src = {
      url = "github:mickael-kerjean/filestash";
      flake = false;
    };
    #    dream2nix.url = "github:nix-community/dream2nix";
    #nixpkgs.follows = "dream2nix/nixpkgs";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs = { self, nixpkgs, flake-parts, filestash-src }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      flake = {
        herculesCI.ciSystems = [ "x86_64-linux" ];
        overlay = final: prev: {
          filestash =
            self.packages.${prev.stdenv.hostPlatform.system}.filestash;
        };
        nixosModule = { pkgs, lib, config, ... }: {
          imports = [ ./nix/filestash-module.nix ];
          nixpkgs.overlays = [ self.overlay ];
        };
      };
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        checks = {
          filestash = pkgs.callPackage ./nix/filestash-vmtest.nix {
            nixosModule = self.nixosModule;
          };
        };
        packages.filestash = pkgs.callPackage ./pkgs/filestash/default.nix {
          inherit filestash-src;
        };
      };
    };
}
