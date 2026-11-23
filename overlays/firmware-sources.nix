# Sources for raspberrypi-firmware, one per tracked kernel.
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/os-specific/linux/firmware/raspberrypi/default.nix
#
# Firmware and kernel are versioned together: `extra/git_hash` in the firmware
# tree names the raspberrypi/linux commit it was built against. Each entry
# here is paired with a kernel in `overlays/linux-and-firmware.nix`; keep the
# two lists in step, and drop an entry here whenever its kernel leaves
# `pkgs/linux-rpi/linux-sources.nix`.
#
# The `version` date becomes the package suffix, e.g. `1.20260408` ->
# `raspberrypifw_20260408`.
[
  {
    # firmware master HEAD, 2026-10-21. Untagged upstream: the newest tag is
    # 1.20260915, which points at 6f0881cb (2026-09-14) and so predates this.
    # `extra/git_hash` is 7bc8e3eb (rpi-6.18.y, 6.18.58): the vendor has still
    # cut no firmware release paired with rpi-7.2.y, so the newest firmware
    # remains the closest match for the v7_2_12 bundle.
    version = "0-unstable-20261021";
    rev = "88a0ae8876e800801ee5c27624138b3d02a21c63";
    srcHash = "sha256-VB9j2So7zbc90MXG8UoDNSdb/1j4zuc2E7GATT/Yf4U=";
  }
  {
    # this release is untagged in the upstream
    # matches unstable kernel `raspberrypi/linux` 6.18.52
    version = "0-unstable-20260915";
    rev = "bead686816848038563a542dc854346ab13253a2";
    srcHash = "sha256-o8elbB6ooTuFEB+fd0gZlu+mGqNlKHQHy2va+bCEMv8=";
  }
  {
    # https://github.com/raspberrypi/firmware/releases/tag/1.20260408
    # matches unstable kernel `raspberrypi/linux` 6.12.87
    version = "1.20260408";
    tag = "1.20260408";
    srcHash = "sha256-4+eqk+3WxSZRfaGyRIW3zGC6ABo50PKGke0en2IvgXk=";
  }
]
