# One kernel derivation per (board model, tracked version), named
# `linux_rpi<model>_v<version>`, e.g. `linux_rpi5_v7_2_12`.
#
# `pkgs/linux-rpi/linux-sources.nix` decides which versions exist. An entry
# there may carry per-version build arguments as well as its source — e.g.
# `structuredExtraConfig`, `fixupStructuredConfig` or `kernelPatches` — and
# they are merged over the common arguments below. The merge is recursive so
# that a version adding its own `kernelPatches` extends the common list
# instead of silently replacing it.
let
  # the latter value is retained when it can't be merged
  recursiveMerge =
    pkgs:
    with pkgs.lib;
    attrList:
    let
      f =
        attrPath:
        zipAttrsWith (
          n: values:
          if tail values == [ ] then
            head values
          else if all isList values then
            unique (concatLists values)
          else if all isAttrs values then
            f (attrPath ++ [ n ]) values
          else
            last values
        );
    in
    f [ ] attrList;

  sources = import ../pkgs/linux-rpi/linux-sources.nix;

  # `6.12.87` -> `v6_12_87`, the key used throughout the flake.
  versionKey = source: "v${builtins.replaceStrings [ "." ] [ "_" ] source.modDirVersion}";

  # Every tracked version builds for every board model. Publishing (what CI
  # builds and pushes to the cache) is narrower — see `packages` in flake.nix.
  models = [
    "02"
    "3"
    "4"
    "5"
  ];

  mkLinux = pkgs: source: rpiModel: {
    # as in https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/linux-kernels.nix
    "linux_rpi${rpiModel}_${versionKey source}" = pkgs.callPackage ../pkgs/linux-rpi/package.nix (
      recursiveMerge pkgs [
        {
          kernelPatches =
            with pkgs.kernelPatches;
            [
              bridge_stp_helper
              request_key_helper
            ]
            # linux-headers >= 7.3 use __u128 in the arm64 UAPI headers, and
            # older kernel trees lack the matching typedef in tools/, which
            # breaks tools/bpf/resolve_btfids. Same backport nixpkgs applies
            # to its own kernels < 7.3 (NixOS/nixpkgs#581990), via upstream
            # nvmd/nixos-raspberrypi@6fdf35c.
            #
            # Dormant here: this flake's nixpkgs (26.05) ships 6.18 headers
            # and no such patch, so both guards are false. It arms itself if
            # the nixpkgs input ever moves to a channel with 7.3+ headers,
            # which is where every kernel below would otherwise stop
            # building.
            ++ pkgs.lib.optional (
              pkgs.kernelPatches ? tools_128bit_types && pkgs.lib.versionOlder source.modDirVersion "7.3"
            ) tools_128bit_types;

          # The Compute Blade's agent mmaps /dev/mem to reach the GPIO and PWM
          # peripheral registers that drive the fan and the edge LEDs; both
          # vendor defconfigs leave the restrictions off for exactly that kind
          # of bare-metal access. nixpkgs' common-config.nix turns them back on
          # for every kernel it builds, so say it again here — in the kernel
          # this repo publishes, rather than in each consumer, where it would
          # cost a from-source rebuild of a kernel the cache already holds.
          structuredExtraConfig = with pkgs.lib.kernel; {
            STRICT_DEVMEM = no;
            IO_STRICT_DEVMEM = no;
          };

          # Per-defconfig, keyed the way pkgs/linux-rpi/package.nix reads it:
          # <defconfig base>.<arch>.
          fixupStructuredConfig = with pkgs.lib.kernel; {
            bcm2711.aarch64 = {
              # bcm2711_defconfig ships ARM64_VA_BITS_39 — a 512 GiB
              # per-process virtual address space, too small for the up-front
              # reservations LMDB and the GHC RTS make.
              ARM64_VA_BITS_48 = yes;
            };
          };

          inherit rpiModel;
        }
        source
      ]
    );
  };

in
final: prev:
prev.lib.mergeAttrsList (prev.lib.concatMap (source: map (mkLinux final source) models) sources)
