# Vendor firmware: boot firmware and device trees from `raspberrypi/firmware`
# (one `raspberrypifw_<date>` per entry in ./firmware-sources.nix), plus the
# wireless/bluetooth blobs from `RPi-Distro`.
#
# Only the wireless firmware revisions paired with a tracked kernel are kept
# here; `overlays/linux-and-firmware.nix` does the pairing.
let
  allFirmware = import ./firmware-sources.nix;

  firmwareVersion =
    pkgs: attrsFor:
    let
      # Gets date of the release from the `version` which is always on the
      # last position in the list of strings splitted by version separators
      # e.g. `1.20250915` -> `20250915`
      cleanVersion =
        let
          noDots = builtins.replaceStrings [ "." "-" ] [ "_" "_" ] attrsFor.version;
          splittedVersion = pkgs.lib.splitString "_" noDots;
        in
        builtins.elemAt splittedVersion ((builtins.length splittedVersion) - 1);
    in
    {
      "raspberrypifw_${cleanVersion}" = pkgs.raspberrypifw.overrideAttrs (_: {
        inherit (attrsFor) version;
        src = pkgs.fetchFromGitHub {
          owner = "raspberrypi";
          repo = "firmware";

          # rev can be used both for rev hash and the tag
          rev = if (attrsFor ? rev) then attrsFor.rev else attrsFor.tag;
          hash = attrsFor.srcHash;
        };
      });
    };

in
_final: prev:
prev.lib.mergeAttrsList (map (firmwareVersion prev) allFirmware)
// {

  # paired with the v7_2_12 and v6_18_52 kernels
  raspberrypiWirelessFirmware_20260321 = prev.raspberrypiWirelessFirmware.overrideAttrs (_: {
    version = "2026-03-21";
    srcs = [
      # https://github.com/RPi-Distro/bluez-firmware/commits/pios/trixie
      # 1.2-13+rpt2 release – 20251002
      (prev.fetchFromGitHub {
        name = "bluez-firmware";
        owner = "RPi-Distro";
        repo = "bluez-firmware";
        rev = "cdf61dc691a49ff01a124752bd04194907f0f9cd";
        hash = "sha256-35pnbQV/zcikz9Vic+2a1QAS72riruKklV8JHboL9NY=";
      })
      # https://github.com/RPi-Distro/firmware-nonfree/commits/trixie
      # 1.20250410-2+rpt1 - 20260321
      (prev.fetchFromGitHub {
        name = "firmware-nonfree";
        owner = "RPi-Distro";
        repo = "firmware-nonfree";
        rev = "9794282eb9f4a2de1f23b41a738926740e975d83";
        hash = "sha256-OtA8yHvfusGP/ucf8Exzi+nSUmNoYp10u+luC2gbNZc=";
      })
    ];
  });

  # paired with the v6_12_87 kernel
  raspberrypiWirelessFirmware_20251008 = prev.raspberrypiWirelessFirmware.overrideAttrs (_: {
    version = "2025-10-02";
    srcs = [
      # https://github.com/RPi-Distro/bluez-firmware/commits/pios/trixie
      # 1.2-13+rpt2 release – 20251002
      (prev.fetchFromGitHub {
        name = "bluez-firmware";
        owner = "RPi-Distro";
        repo = "bluez-firmware";
        rev = "cdf61dc691a49ff01a124752bd04194907f0f9cd";
        hash = "sha256-35pnbQV/zcikz9Vic+2a1QAS72riruKklV8JHboL9NY=";
      })
      # https://github.com/RPi-Distro/firmware-nonfree/commits/trixie
      # 20241210-1+rpt3 - 20250930
      (prev.fetchFromGitHub {
        name = "firmware-nonfree";
        owner = "RPi-Distro";
        repo = "firmware-nonfree";
        rev = "e90d6888e745eb9ee1aab098fff001edc31b95b7";
        hash = "sha256-+MO0VOwttfTT9hX5lMmMRAaDzmWh2dFxsH/FRDTFzjs";
      })
    ];
  });

}
