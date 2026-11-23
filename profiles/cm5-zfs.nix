# Compute Module 5 with ZFS: the newest kernel bundle OpenZFS supports.
import ./compute-module.nix {
  variant = "5";
  zfs = true;
}
