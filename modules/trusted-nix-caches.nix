# The caches this flake's own artefacts come from, added to the machines it
# builds. `lib.nixosSystem` and friends import this unless called with
# `trustCaches = false`.
#
# nix.channings.me holds what CI builds here: the kernels (with their `dev`
# outputs, so out-of-tree modules build against them without rebuilding the
# kernel) and the profile closures. The cachix cache is upstream
# nvmd/nixos-raspberrypi's, kept because it costs nothing to consult.
let
  substituters = [
    "https://nix.channings.me"
    "https://nixos-raspberrypi.cachix.org"
  ];
in
{
  nix.settings.substituters = substituters;
  # Caches in trusted-substituters can be used by unprivileged users i.e. in
  # flakes but are not enabled by default.
  nix.settings.trusted-substituters = substituters;
  nix.settings.trusted-public-keys = [
    "garage:JZet/fsItH8cJ6SKLci1+BuMIQGDfZSa/8GxGpKcxss="
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  ];
}
