# Vendor kernel sources (raspberrypi/linux) tracked by this fork.
#
# This list is the single source of truth for which kernels exist here: every
# `linux_rpi<model>_v<version>` package, every `linuxAndFirmware.v<version>`
# bundle, and therefore every profile, derives from it. Keep it short — each
# entry that a profile selects is ~1.5h of CI time per board, and each entry
# that no profile selects is dead weight.
#
# Ordered newest first. `overlays/linux-and-firmware.nix` consumes that order:
# `latest` is the head, `zfs` is the first entry OpenZFS still supports.
#
# Adding a version:
#   1. add it here, newest first, with the firmware it pairs with added to
#      `overlays/firmware-sources.nix` (match `extra/git_hash` in the firmware
#      tree against the kernel's rev),
#   2. pair the two in `overlays/linux-and-firmware.nix`,
#   3. `just test` to confirm every profile still evaluates.
#
# Removing a version: anything the `zfs` ladder may still need must stay —
# see the comment on that alias.
#
# NOTE: srcHash must be computed on a case-sensitive filesystem.
# raspberrypi/linux carries case-colliding headers (e.g. netfilter
# xt_CONNMARK.h vs xt_connmark.h); a macOS unpack silently drops the
# uppercase partners and yields a hash that fails on every Linux builder.
[
  {
    # rpi-7.2.y branch HEAD, 2026-10-25. The `latest` bundle, and what the
    # cm4/cm5 profiles run.
    modDirVersion = "7.2.12";
    tag = "unstable_20261025";
    rev = "ce7147911b8d523c46726045ff2f7adf85bc9cb8"; # 7.2.12
    srcHash = "sha256-zkn5FPBCRy/gqPfUOa7JgEHc16ylqymHNbOgqfJTSNA=";
  }
  {
    # rpi-6.18.y, first rung below `latest` on the ZFS ladder.
    modDirVersion = "6.18.52";
    tag = "unstable_20260915";
    rev = "4bb240615790ea5bd939484f4595b6952ac94ef4";
    srcHash = "sha256-aI1Rqihe3nV3th2/gEKS4Y1A9AClT9l5688WROiVRrM=";
  }
  {
    # rpi-6.12.y (LTS), the floor of the ZFS ladder: whatever OpenZFS drops
    # support for above, this stays supported for years.
    modDirVersion = "6.12.87";
    tag = "unstable_20260509";
    rev = "ae4d75fb36deba0fe1a986d9bfae65755e082dd0"; # 6.12.87
    srcHash = "sha256-vAjVe2f3+1+6HZCp7hfCEvS4XE2OveIRe/+3+oSFdZI=";
  }
]
