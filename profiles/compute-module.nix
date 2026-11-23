# The profile behind `nixosModules.profiles.cm4`, `cm4-zfs`, `cm5` and
# `cm5-zfs` — see ./cm4.nix and friends, which are the names you import.
#
# A profile is the second half of what this flake publishes (the first being
# the kernel itself): it pins a blade to one of the kernel bundles built and
# cached by this repo, so that a `nixos-rebuild` on a Compute Module pulls a
# kernel from the cache instead of spending an hour building one.
#
# Everything here comes from `nixos-raspberrypi.legacyPackages.<system>`, this
# flake's own RPi package set — the exact derivations CI builds and pushes
# (`packages.<system>` re-exports them for `nix-build -A`). A profile that
# reached for the importing configuration's own `pkgs` instead would be at the
# mercy of which overlays that configuration applies, and would silently miss
# the cache the moment they differed.
#
# Arguments:
#   variant  "4" for CM4, "5" for CM5 — the Raspberry Pi board the compute
#            module is, which decides the defconfig (bcm2711 vs bcm2712),
#            the bootloader and the firmware layout
#   zfs      whether to track the `zfs` kernel bundle and enable ZFS, rather
#            than tracking `latest`
#
# What is deliberately *not* here:
#   * `networking.hostId`, which ZFS requires and which must be unique per
#     machine — NixOS asserts on it, so a zfs profile without one fails loudly
#   * 16K pages on CM5 (`raspberry-pi-5.page-size-16k`): a different kernel
#     build, so importing it is an hour of compiling and a cache miss. Import
#     it yourself if you want it, and expect to build.
#   * filesystems, users, and the rest of the machine — profiles describe the
#     blade, not the deployment.
{
  variant,
  zfs ? false,
}:

{
  lib,
  pkgs,
  nixos-raspberrypi,
  ...
}:

let
  rpi = nixos-raspberrypi.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # A bundle is a kernel together with the firmware revisions it was built
  # against; the aliases are resolved in overlays/linux-and-firmware.nix.
  bundle = rpi.linuxAndFirmware.${if zfs then "zfs" else "latest"};

  kernelPackages = bundle."linuxPackages_rpi${variant}";
in
{
  imports = [
    nixos-raspberrypi.nixosModules."raspberry-pi-${variant}".base
  ];

  # The board module picks the `latest` bundle with `mkDefault` (priority
  # 1000). Priority 900 overrides that for the zfs profiles while staying
  # weaker than an ordinary definition, so a configuration importing this
  # profile can still set its own kernel without `mkForce`.
  boot.kernelPackages = lib.mkOverride 900 kernelPackages;
  boot.loader.raspberry-pi.firmwarePackage = lib.mkOverride 900 bundle.raspberrypifw;

  # CM5's board default is `kernelboot`, which this flake deprecates and will
  # remove; `kernel` is its supported successor and keeps a generation list
  # in the firmware partition, so a bad rebuild on a headless blade is a
  # rollback rather than a trip to the rack. CM4's default (`uboot`) is not
  # deprecated, and switching a booting machine's bootloader is not something
  # a kernel profile should do uninvited, so it is left alone.
  boot.loader.raspberry-pi.bootloader = lib.mkIf (variant == "5") (lib.mkOverride 900 "kernel");

  # `boot.kernelPackages` above only covers the kernel. Anything reaching for
  # the firmware through `pkgs` — `hardware.enableRedistributableFirmware`
  # pulling in `raspberrypiWirelessFirmware`, say — resolves to the `default`
  # bundle unless redirected, which would leave a zfs blade running its own
  # kernel with the latest kernel's blobs. Redirect the whole bundle so the
  # pairing holds however a package is reached.
  nixpkgs.overlays = [
    (_final: _prev: {
      inherit (bundle) raspberrypifw raspberrypiWirelessFirmware;
      "linux_rpi${variant}" = bundle."linux_rpi${variant}";
      "linuxPackages_rpi${variant}" = kernelPackages;
    })
  ];

  # The kernel module is built against the kernel above, so a cached kernel
  # (with its `dev` output, which is what the module build consumes) is the
  # difference between a minute and an hour here.
  boot.supportedFilesystems.zfs = zfs;

  # The 26.11 default, taken early: forcing an import ignores the hostId
  # guard that stops two machines mounting the same pool. Blades that boot
  # from a pool another blade may have left dirty can set it back to true.
  boot.zfs.forceImportRoot = lib.mkIf zfs (lib.mkDefault false);

  system.nixos.tags = [
    "cm${variant}"
  ]
  ++ lib.optional zfs "zfs";
}
