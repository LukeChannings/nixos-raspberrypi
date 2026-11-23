# Compute Module 4 with ZFS: the newest kernel bundle OpenZFS supports.
import ./compute-module.nix {
  variant = "4";
  zfs = true;
}
