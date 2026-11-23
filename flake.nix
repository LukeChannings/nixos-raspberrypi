{
  description = "Raspberry Pi kernels, firmware and Compute Module profiles for NixOS, built and cached in this repository";

  nixConfig = {
    extra-substituters = [
      # Everything this flake publishes: the kernels, the firmware they are
      # paired with, and the profile closures built from them.
      "https://nix.channings.me"
      # Upstream nvmd/nixos-raspberrypi's cache. Only useful for packages
      # whose derivation this fork has not changed, but free to consult.
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "garage:JZet/fsItH8cJ6SKLci1+BuMIQGDfZSa/8GxGpKcxss="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Lets `nix-build` / `nix-shell` use the pinned inputs without flake
    # commands copying the whole source tree to the store. See ./default.nix.
    flake-compat = {
      url = "git+https://git.lix.systems/lix-project/flake-compat";
      flake = false;
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    argononed = {
      url = "github:nvmd/argononed";
      flake = false;
    };

    nixos-images = {
      url = "github:nvmd/nixos-images/sdimage-installer";
      inputs.nixos-stable.follows = "nixpkgs";
      inputs.nixos-unstable.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      argononed,
      nixos-images,
      ...
    }:
    let
      # Module groups here are nested attrsets — `raspberry-pi-5.base`,
      # `profiles.cm5-zfs` — and flake-parts types `flake.nixosModules` as
      # deferred modules, which would coerce each group into one module and
      # take `.base` with it. So they are defined out here and merged into
      # the outputs below, untouched.
      nixosModules = {
        trusted-nix-caches = import ./modules/trusted-nix-caches.nix;
        nixpkgs-rpi = import ./modules/nixpkgs-rpi.nix;

        bootloader = import ./modules/system/boot/loader/raspberrypi;
        default = import ./modules/raspberrypi.nix;

        sd-image = import ./modules/installer/sd-card/sd-image-raspberrypi.nix;

        pisugar-3 = import ./modules/pisugar-3.nix;

        usb-gadget-ethernet = import ./modules/usb-gadget-ethernet.nix;

        # The blades this fork exists for: a Compute Module pinned to one of
        # the kernel bundles built and cached here. The `-zfs` pair tracks
        # the newest bundle OpenZFS supports and enables it.
        profiles = {
          cm4 = import ./profiles/cm4.nix;
          cm4-zfs = import ./profiles/cm4-zfs.nix;
          cm5 = import ./profiles/cm5.nix;
          cm5-zfs = import ./profiles/cm5-zfs.nix;
        };

        raspberry-pi-5 = {
          base = import ./modules/raspberry-pi-5;
          display-vc4 = import ./modules/display-vc4.nix;
          display-rp1 = import ./modules/raspberry-pi-5/display-rp1.nix;
          bluetooth = import ./modules/bluetooth.nix;
          page-size-16k = import ./modules/raspberry-pi-5/page-size-16k.nix;
        };

        raspberry-pi-4 = {
          base = import ./modules/raspberry-pi-4.nix;
          display-vc4 = import ./modules/display-vc4.nix;
          bluetooth = import ./modules/bluetooth.nix;
          # work-in-progress, untested
          case-argonone = import ./modules/case-argononev2.nix { inherit argononed; };
        };

        raspberry-pi-3 = {
          base = import ./modules/raspberry-pi-3.nix;
        };

        raspberry-pi-02 = {
          base = import ./modules/raspberry-pi-02.nix;
          display-vc4 = import ./modules/display-vc4.nix;
          bluetooth = import ./modules/bluetooth.nix;
        };
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } (
      { lib, ... }:
      let
        # The only architecture this fork builds for. Compute Module 4 and 5
        # are both aarch64; the 32-bit package sets upstream carries went with
        # the boards this fork does not run.
        rpiSystem = "aarch64-linux";

        # "RPi world": nixpkgs with all overlays applied "globally", i.e. all
        # packages here depend on rpi's/optimized versions of the dependencies
        # * used inside the modules, where a choice of "sane defaults" about
        #   the nixpkgs channel had to be made
        # * the binary cache is generated from this package set
        mkRpiPkgs =
          system:
          import nixpkgs {
            inherit system;
            overlays = [
              self.overlays.pkgs

              self.overlays.bootloader
              self.overlays.vendor-kernel
              self.overlays.vendor-firmware
              self.overlays.kernel-and-firmware

              self.overlays.vendor-pkgs
            ];
          };

        # A machine per profile, minimal enough that building it caches the
        # parts a blade shares with it and nothing else. See
        # ./profiles/reference-system.nix.
        mkReferenceSystem =
          hostName: profile:
          self.lib.nixosSystem {
            modules = [
              (import ./profiles/reference-system.nix { inherit hostName profile; })
            ];
          };

        mkInstaller =
          variant: modules:
          self.lib.nixosInstaller {
            specialArgs = inputs // {
              nixos-raspberrypi = self;
            };
            modules = [
              nixos-images.nixosModules.sdimage-installer
              (
                {
                  config,
                  lib,
                  modulesPath,
                  ...
                }:
                {
                  disabledModules = [
                    # disable the sd-image module that nixos-images uses
                    (modulesPath + "/installer/sd-card/sd-image-aarch64-installer.nix")
                  ];
                  # nixos-images sets this with `mkForce`, thus `mkOverride 40`
                  image.baseName =
                    let
                      cfg = config.boot.loader.raspberry-pi;
                    in
                    lib.mkOverride 40 "nixos-installer-rpi${cfg.variant}-${cfg.bootloader}";

                  # nixos-images' installer Wi-Fi module uses iwd and disables
                  # the legacy wpa_supplicant path. NixOS 26.05 enables it via
                  # NetworkManager, so keep the installer module's intent.
                  networking.wireless.enable = lib.mkForce false;

                  imports = [
                    nixosModules."raspberry-pi-${variant}".base
                  ];

                  system.nixos.tags =
                    let
                      cfg = config.boot.loader.raspberry-pi;
                    in
                    [
                      "raspberry-pi-${cfg.variant}"
                      cfg.bootloader
                      config.boot.kernelPackages.kernel.version
                    ];
                }
              )
            ]
            ++ modules;
          };

        # Instantiate a derivation without building it. A kernel takes the
        # better part of an hour and an image tens of gigabytes, but
        # evaluating either takes seconds and catches what matters most here:
        # a profile that no longer evaluates, or a bundle whose kernel and
        # firmware no longer line up.
        evalCheck =
          pkgs: name: drvs:
          pkgs.writeText "eval-${name}" (
            lib.concatMapStringsSep "\n" (drv: builtins.unsafeDiscardOutputDependency drv.drvPath) drvs
          );
      in
      {
        imports = [ inputs.treefmt-nix.flakeModule ];

        systems = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-darwin"
          "x86_64-linux"
        ];

        flake = {
          lib = import ./lib (
            {
              inherit (nixpkgs) lib;
            }
            // inputs
          );

          overlays = {
            bootloader = import ./overlays/bootloader.nix;

            pkgs = import ./overlays/pkgs.nix;
            vendor-pkgs = import ./overlays/vendor-pkgs.nix;
            jemalloc-page-size-16k = import ./overlays/jemalloc-page-size-16k.nix;

            vendor-firmware = import ./overlays/vendor-firmware.nix;
            vendor-kernel = import ./overlays/vendor-kernel.nix;

            kernel-and-firmware = import ./overlays/linux-and-firmware.nix;

            libpisp-default-config-path = import ./overlays/libpisp-default-config-path.nix;
          };

          nixosConfigurations = {
            # One reference system per published profile. Their toplevels are
            # what the Build workflow pushes to the cache, so that a blade
            # importing the profile has nothing left to build.
            cm4 = mkReferenceSystem "cm4" nixosModules.profiles.cm4;
            cm4-zfs = mkReferenceSystem "cm4-zfs" nixosModules.profiles.cm4-zfs;
            cm5 = mkReferenceSystem "cm5" nixosModules.profiles.cm5;
            cm5-zfs = mkReferenceSystem "cm5-zfs" nixosModules.profiles.cm5-zfs;

            # Installer images, for putting NixOS on a blade in the first
            # place. Built on demand (see .github/workflows/installer.yaml),
            # not cached: they are multi-gigabyte and single-use.
            rpi4-installer = mkInstaller "4" [ ];
            rpi5-installer = mkInstaller "5" [
              { imports = [ nixosModules.raspberry-pi-5.page-size-16k ]; }
            ];
          };
        };

        perSystem =
          {
            config,
            pkgs,
            system,
            ...
          }:
          {
            treefmt = ./treefmt.nix;

            legacyPackages = lib.optionalAttrs (system == rpiSystem) (mkRpiPkgs system);

            # The published set: what CI builds, what the cache holds, and
            # what `nix-build -A <attr>` is for. Everything else this flake
            # can build stays in `legacyPackages`, uncached and unpromised.
            #
            # Unsuffixed names are the `latest` bundle; `-zfs` names are the
            # newest bundle OpenZFS supports. While OpenZFS keeps up with the
            # vendor kernel the two are the same derivation, and the second
            # build of each pair is a no-op.
            packages = lib.optionalAttrs (system == rpiSystem) (
              let
                rpi = self.legacyPackages.${rpiSystem};
                inherit (rpi.linuxAndFirmware) latest zfs;
                toplevel = name: self.nixosConfigurations.${name}.config.system.build.toplevel;
                sdImage = name: self.nixosConfigurations.${name}.config.system.build.sdImage;
              in
              {
                inherit (latest)
                  linux_rpi4
                  linux_rpi5
                  raspberrypifw
                  raspberrypiWirelessFirmware
                  ;

                linux_rpi4-zfs = zfs.linux_rpi4;
                linux_rpi5-zfs = zfs.linux_rpi5;
                raspberrypifw-zfs = zfs.raspberrypifw;
                raspberrypiWirelessFirmware-zfs = zfs.raspberrypiWirelessFirmware;

                inherit (rpi) raspberrypi-utils;
                raspberrypi-udev-rules = rpi.callPackage ./pkgs/raspberrypi/udev-rules.nix { };

                cm4-system = toplevel "cm4";
                cm4-zfs-system = toplevel "cm4-zfs";
                cm5-system = toplevel "cm5";
                cm5-zfs-system = toplevel "cm5-zfs";

                installer-rpi4 = sdImage "rpi4-installer";
                installer-rpi5 = sdImage "rpi5-installer";
              }
            );

            # `just test` builds these: one evaluation check per NixOS
            # configuration, one covering every published package, plus the
            # treefmt check contributed by treefmt-nix.
            checks =
              (lib.mapAttrs' (
                name: nixosConfig:
                lib.nameValuePair "eval-${name}" (evalCheck pkgs name [ nixosConfig.config.system.build.toplevel ])
              ) self.nixosConfigurations)
              // {
                # Evaluation does not depend on the host, so check the
                # aarch64 packages everywhere — including from an x86_64
                # workstation, which builds none of them itself.
                eval-packages = evalCheck pkgs "packages" (lib.attrValues self.packages.${rpiSystem});
              };

            devShells.default = pkgs.mkShell {
              name = "nixos-raspberrypi";
              packages = [
                pkgs.just
                config.treefmt.build.wrapper

                pkgs.nixd # lsp language server for nix
                pkgs.nix-output-monitor
                pkgs.bash-language-server
                pkgs.shellcheck
                # pushing a kernel to nix.channings.me by hand, the way the
                # Build workflow does it
                pkgs.niks3
                pkgs.gh
              ];
            };
          };
      }
    )
    // {
      inherit nixosModules;
    };
}
