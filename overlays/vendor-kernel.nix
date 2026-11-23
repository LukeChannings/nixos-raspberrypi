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
          kernelPatches = with pkgs.kernelPatches; [
            bridge_stp_helper
            request_key_helper
          ];
          inherit rpiModel;
        }
        source
      ]
    );
  };

in
final: prev:
prev.lib.mergeAttrsList (prev.lib.concatMap (source: map (mkLinux final source) models) sources)
