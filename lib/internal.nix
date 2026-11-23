{ lib, self, ... }:

{
  nixosSystemRPi =
    {
      nixpkgs ? self.inputs.nixpkgs,
      trustCaches ? true,
      rpiModules,
    }:
    args:
    nixpkgs.lib.nixosSystem (
      builtins.removeAttrs args [
        "nixpkgs"
        "trustCaches"
      ]
      // {
        specialArgs = (args.specialArgs or { }) // {
          nixos-raspberrypi = self;
        };
        modules =
          rpiModules
          # Nix caches with prebuilt packages, see `packages` in flake.nix
          # for what this repository builds and pushes to them
          ++ lib.optional trustCaches self.nixosModules.trusted-nix-caches
          # User modules
          ++ args.modules;
      }
    );

  full-nixos-raspberrypi-config =
    { ... }:
    {
      imports = with self.nixosModules; [
        self.lib.int.default-nixos-raspberrypi-config
        # Optonally add overlays with optimised packages into the global scope
        self.lib.inject-overlays-global
      ];
    };

  default-nixos-raspberrypi-config =
    { ... }:
    {
      # the only fully supported architecture
      nixpkgs.hostPlatform = "aarch64-linux";

      imports = with self.nixosModules; [
        # All RPi and RPi-optimised packages to be available in `pkgs.rpi`
        nixpkgs-rpi
        # Add necessary overlays with kernel, firmware, vendor packages
        self.lib.inject-overlays
      ];
    };

}
