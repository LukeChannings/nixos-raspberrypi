# Kernel bundles: a vendor kernel with the firmware revisions it was built
# against, exposed as `pkgs.linuxAndFirmware.<alias or version>`.
#
# Three aliases sit on top of the per-version bundles:
#
#   latest   the newest kernel this fork tracks — what the cm4/cm5 profiles
#            run, and what `default` points at
#   zfs      the newest tracked kernel OpenZFS still supports — what the
#            cm4-zfs/cm5-zfs profiles run
#   default  what `pkgs.linux_rpi<model>` and friends resolve to for anything
#            that does not ask for a bundle by name
#
# `zfs` is computed, not pinned. OpenZFS declares the kernel range it builds
# against (`kernelMinSupportedMajorMinor`/`kernelMaxSupportedMajorMinor` in
# nixpkgs, surfaced as `meta.broken` on the kernel module), and that ceiling
# moves with every nixpkgs bump. So the alias walks the tracked versions
# newest-first and takes the first one whose kernel module is not broken,
# which means:
#
#   * while OpenZFS keeps up with the vendor kernel, `zfs` == `latest` and the
#     -zfs profiles cost no extra build,
#   * when the vendor jumps ahead of OpenZFS, `zfs` falls back a rung by
#     itself — no one has to notice and edit a pin,
#   * a version can only be removed from `pkgs/linux-rpi/linux-sources.nix`
#     once nothing below it is needed as a rung; removing them all makes this
#     throw rather than silently publish a ZFS-less kernel.
let
  # linux kernel with compatible firmware
  mkBundle = final: name: firmware: {
    "${name}" = rec {
      linux_rpi5 = final."linux_rpi5_${name}";
      linux_rpi4 = final."linux_rpi4_${name}";
      linux_rpi3 = final."linux_rpi3_${name}";
      linux_rpi02 = final."linux_rpi02_${name}";

      linuxPackages_rpi5 = final.linuxPackagesFor linux_rpi5;
      linuxPackages_rpi4 = final.linuxPackagesFor linux_rpi4;
      linuxPackages_rpi3 = final.linuxPackagesFor linux_rpi3;
      linuxPackages_rpi02 = final.linuxPackagesFor linux_rpi02;
    }
    // (with firmware; {
      # Matching versions of the firmware to the kernel:
      # - https://downloads.raspberrypi.com/raspios_arm64/release_notes.txt
      # - `extra/git_hash` https://github.com/raspberrypi/firmware/ matches
      #   the hash of the https://github.com/raspberrypi/linux

      # used by
      # - `modules/installer/sd-card/sd-image-{aarch64,armv7l-multiplatform,raspberrypi}`,
      # - `omxplayer` (likely broken)
      # - `device-tree_rpi` (`raspberrypi-dtbs`)
      raspberrypifw = fw;
      # used by
      # - `modules/hardware/all-firmware.nix` to populate `hardware.firmware` on aarch64
      raspberrypiWirelessFirmware = wFw;
    });
  };

  # Tracked versions, newest first — the same order as
  # `pkgs/linux-rpi/linux-sources.nix`, which is what the aliases below walk.
  versions = [
    "v7_2_12"
    "v6_18_59"
    "v6_12_87"
  ];

  # Does OpenZFS build against this bundle's kernel? `pkgs.zfs` is the
  # userspace package NixOS defaults `boot.zfs.package` to; its
  # `kernelModuleAttribute` names the matching kernel module in a
  # `linuxPackagesFor` set, whose `meta.broken` carries nixpkgs' verdict.
  # Reading `meta` only evaluates — no kernel is built to answer this.
  supportsZfs =
    final: bundle:
    let
      kmod = bundle.linuxPackages_rpi5.${final.zfs.kernelModuleAttribute} or null;
    in
    kmod != null && !(kmod.meta.broken or true);

in
final: prev: {

  inherit (final.linuxAndFirmware.default)
    linux_rpi5
    linuxPackages_rpi5
    linux_rpi4
    linuxPackages_rpi4
    linux_rpi3
    linuxPackages_rpi3
    linux_rpi02
    linuxPackages_rpi02
    raspberrypifw
    raspberrypiWirelessFirmware
    ;

  linuxAndFirmware = prev.lib.mergeAttrsList [

    (mkBundle final "v7_2_12" {
      fw = final.raspberrypifw_20261021;
      wFw = final.raspberrypiWirelessFirmware_20260321;
    })

    (mkBundle final "v6_18_59" {
      fw = final.raspberrypifw_20261027;
      wFw = final.raspberrypiWirelessFirmware_20260321;
    })

    (mkBundle final "v6_12_87" {
      fw = final.raspberrypifw_20260408;
      wFw = final.raspberrypiWirelessFirmware_20251008;
    })

    {
      latest = final.linuxAndFirmware.${builtins.head versions};

      zfs =
        let
          bundles = map (v: final.linuxAndFirmware.${v}) versions;
        in
        prev.lib.findFirst (supportsZfs final) (throw ''
          No kernel in pkgs/linux-rpi/linux-sources.nix is supported by
          ${final.zfs.pname or "zfs"}-${final.zfs.version}. Track an older
          kernel (see the ZFS ladder comment in that file), or pin an
          OpenZFS release that supports one of them.
        '') bundles;

      default = final.linuxAndFirmware.latest;
    }
  ];
}
