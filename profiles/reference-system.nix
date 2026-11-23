# The smallest complete machine that uses a profile.
#
# Profiles are modules, and a module cannot be built — but `toplevel` can, and
# that is what CI builds and pushes to the cache. Everything a blade shares
# with this reference system (kernel, modules, firmware, initrd tooling, the
# ZFS kernel module) is then a cache hit on the blade; what is left to build
# is the part that differs, which is the part that was never ours to cache.
#
# So keep this minimal and boring. Anything opinionated added here is paid for
# in CI time and bought nothing, because a real blade will override it.
{
  hostName,
  profile,
}:

{ lib, ... }:

{
  imports = [ profile ];

  networking.hostName = hostName;

  # ZFS refuses to import pools without one. Reference systems are never
  # deployed, so a fixed value is fine; a real blade must set its own.
  networking.hostId = lib.mkDefault "0a5e2e21";

  # Matches what the sd-image installer lays down.
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
    };
  };

  system.stateVersion = "26.05";
}
