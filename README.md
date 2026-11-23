# nixos-raspberrypi

Raspberry Pi support for [NixOS](https://nixos.org/): bootloader and firmware
infrastructure, vendor kernels, and the Compute Module profiles the hartlandia
blades run.

A fork of [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi),
narrowed to what this fleet uses and made self-contained: the kernel versions
are decided here, built here, and cached here. Nothing waits on an upstream
release or an upstream cache. Upstream's work still arrives, as a sync PR —
see [Syncing with upstream](#syncing-with-upstream).

## What this repository publishes

Two things, and everything else is the machinery that produces them:

| | |
|---|---|
| **a kernel** | the vendor kernel (`raspberrypi/linux`) with the firmware revisions it was built against, for CM4 (bcm2711) and CM5 (bcm2712) |
| **a profile** | `nixosModules.profiles.{cm4,cm4-zfs,cm5,cm5-zfs}` — a Compute Module pinned to one of those kernels |

Both are built on every push to `main` and pushed to
[`nix.channings.me`](https://nix.channings.me), kernels first so that the
profile closures substitute them rather than building a second copy. A blade
importing a profile builds nothing.

The push includes **every output of the kernel, not just `out`** — in
particular `dev`, the configured build tree that out-of-tree modules compile
against. Without it a cached kernel is a trap: ZFS, or any other kernel
module, would rebuild the whole kernel to get at a build tree that already
exists. The derivations go up too, so the cache carries how a kernel was built
and not only what came out of it.

## Two kernels: `latest` and `zfs`

`pkgs/linux-rpi/linux-sources.nix` lists the vendor kernels this fork tracks,
newest first. Two aliases sit on top of it
(`overlays/linux-and-firmware.nix`):

- **`latest`** — the newest tracked kernel. What `cm4` and `cm5` run, and what
  `pkgs.linux_rpi5` and friends resolve to.
- **`zfs`** — the newest tracked kernel OpenZFS still supports. What `cm4-zfs`
  and `cm5-zfs` run.

`zfs` is computed, not pinned. OpenZFS declares the kernel range it builds
against, nixpkgs surfaces that as `meta.broken` on the kernel module, and the
alias walks the tracked versions newest-first and takes the first one that
isn't broken. So while OpenZFS keeps up with the vendor kernel, `zfs` ==
`latest` and the ZFS profiles cost no extra build; when the vendor jumps
ahead, the alias falls back a rung on its own. Nobody has to notice and edit a
pin, and `just test` fails loudly if no tracked kernel is supported at all.

Today both aliases are the same kernel:

```console
$ nix-instantiate --eval -A packages.aarch64-linux.linux_rpi5.version
"7.2.12-unstable_20261025"
```

## Using it

```nix
{
  inputs.nixos-raspberrypi.url = "git+https://forge.channings.me/hartlandia/nixos-raspberrypi.git";

  # Optional, and worth it: this is where the kernels live.
  nixConfig = {
    extra-substituters = [ "https://nix.channings.me" ];
    extra-trusted-public-keys = [
      "garage:JZet/fsItH8cJ6SKLci1+BuMIQGDfZSa/8GxGpKcxss="
    ];
  };
}
```

A blade is then the profile plus the machine:

```nix
nixosConfigurations.blade-01 = nixos-raspberrypi.lib.nixosSystem {
  modules = [
    nixos-raspberrypi.nixosModules.profiles.cm5-zfs

    {
      networking.hostName = "blade-01";
      # ZFS needs one, and it must be unique per machine.
      networking.hostId = "...";

      fileSystems = { /* ... */ };
      system.stateVersion = "26.05";
    }
  ];
};
```

`lib.nixosSystem` passes the flake to the modules and trusts the caches above;
see "Advanced usage" for doing it by hand. `profiles/reference-system.nix` is
the smallest complete example — it is also what CI builds.

### What a profile sets

- the board's base module (`raspberry-pi-4.base` / `raspberry-pi-5.base`)
- `boot.kernelPackages` and the firmware packages, from its kernel bundle, at
  priority 900 — stronger than the board module's `mkDefault`, weaker than an
  ordinary definition, so you can still override it without `mkForce`
- on CM5, `boot.loader.raspberry-pi.bootloader = "kernel"`: the board default
  (`kernelboot`) is deprecated here, and `kernel` keeps a generation list in
  the firmware partition, so a bad rebuild on a headless blade is a rollback
  instead of a trip to the rack. **CM4 is left on `uboot`**, which is not
  deprecated — a kernel profile has no business switching a booting machine's
  bootloader uninvited.
- on the `-zfs` profiles, `boot.supportedFilesystems.zfs` and
  `boot.zfs.forceImportRoot = false` (the 26.11 default, taken early)

Deliberately **not** set: `networking.hostId`, filesystems, users — profiles
describe the blade, not the deployment. Nor 16K pages on CM5
(`raspberry-pi-5.page-size-16k`): that is a different kernel build, so
importing it is an hour of compiling and a guaranteed cache miss.

### Other hardware

Board support beyond CM4/CM5 is kept from upstream but is neither built nor
cached here — expect to compile:

```nix
imports = with nixos-raspberrypi.nixosModules; [
  raspberry-pi-02.base
  raspberry-pi-3.base
  raspberry-pi-4.base
  raspberry-pi-5.base

  usb-gadget-ethernet      # Ethernet emulation over USB

  raspberry-pi-4.display-vc4   # RPi4: the only display option

  # RPi5: one of these for the "PrimaryGPU" configuration
  raspberry-pi-5.display-vc4   # "regular" display connected
  raspberry-pi-5.display-rp1   # RP1-connected (DPI/composite/MIPI DSI)
  raspberry-pi-5.page-size-16k # 16k pages (rebuilds the kernel)
];
```

## Bootloader infrastructure

Manages the Raspberry Pi firmware partition `/boot/firmware` (the path is
configurable with `boot.loader.raspberry-pi.firmwarePath`).

Partition provisioning is integrated with bootloader activation scripts,
happening on NixOS generation switch, which is what lets deployment tools like
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere/) work
without interactive intervention (`kexec` is, unfortunately, not supported).

Supported boot methods (`boot.loader.raspberry-pi.bootloader`):

- `kernel` — new generation of `kernelboot`, supporting multiple NixOS
  generations (see [#60](https://github.com/nvmd/nixos-raspberrypi/issues/60));
  what the CM5 profiles use and what is _recommended_ for new installations
- `uboot` — board default for everything other than RPi5
- `kernelboot` (legacy) — board default for RPi5, deprecated

Raspberry's `config.txt` is configured with `hardware.raspberry-pi.config`
options; see `modules/configtxt.nix` for the defaults, translated from
Raspberry Pi OS. Bootloader options live in `boot.loader.raspberry-pi`
(`modules/system/boot/loader/raspberrypi/default.nix`).

## Installer images

SD card images for RPi4 and RPi5, based on
[nixos-images](https://github.com/nix-community/nixos-images): mDNS enabled,
`iwd` for easier wlan configuration, and a partition table that expands to
fill the card on first boot, so an image doubles as a ready-to-use system.

```sh
just build installer-rpi5
```

They are built weekly (and on demand) by the Installer images workflow, which
keeps them as artefacts rather than pushing them to the cache: multi-gigabyte,
single-use, and nothing substitutes from them. Randomly generated connection
credentials are displayed on screen once the system boots.

## Development

Vanilla `nix-build` / `nix-shell`, never `nix build` / `nix develop`: the
flake exists to pin inputs, and flake commands copy the whole source tree to
the store on every invocation.

```sh
just            # list recipes
just test       # evaluate every profile, installer and published package
just lint       # treefmt over the working tree (nix, yaml, workflows)
just format     # same, writing changes
just build linux_rpi5   # needs an aarch64 builder: native, remote or binfmt
```

`just test` is cheap and catches what matters: a kernel takes the better part
of an hour and an image tens of gigabytes, but *evaluating* them takes seconds
and is what notices a profile that no longer builds or a bundle whose kernel
and firmware no longer line up.

Everything published is `aarch64-linux`, so `packages` is empty on an x86_64
workstation and `just build` there needs emulation or a remote builder. CI
builds natively on arm runners instead.

| workflow | where | what |
|---|---|---|
| Lint, Test | Forgejo + GitHub | `just lint`, `just test` |
| Build | GitHub (`ubuntu-24.04-arm`) | kernels, then profile closures → `nix.channings.me` |
| Installer images | GitHub (`ubuntu-24.04-arm`) | sd-images as artefacts, weekly |
| Update flake.lock | GitHub | weekly PR |
| Upstream sync | Forgejo | weekly `sync/upstream` PR |

Build lives on GitHub because its arm64 runners are what make a native
aarch64 kernel build free.

### Syncing with upstream

Upstream's commits come in through a `sync/upstream` PR against `main`, opened
weekly by the Upstream sync workflow. It tracks upstream's **`develop`**: this
fork branched from there and carries commits upstream's `main` has not
promoted yet, so develop is the branch our history actually continues.

The workflow never resolves anything. A merge that conflicts is left for a
person — nothing is pushed, and the conflicting paths land in the job log and
on the PR. Expect conflicts in the places this fork deliberately diverges:
`flake.nix`, `overlays/`, `pkgs/linux-rpi/`, the workflows and this README.
When a sync touches the kernel lists, the question to ask is not "what did
upstream change" but "does this fleet want that kernel" — see below.

When resolving a sync PR: merge it with a merge commit or a fast-forward,
**never squash it**, and bring `main` into it by merging rather than rebasing.
Rewriting upstream's commits makes every later sync conflict with the
rewritten copies.

To merge by hand instead:

```sh
git remote add upstream https://github.com/nvmd/nixos-raspberrypi.git
git fetch upstream develop
git merge upstream/develop
```

### Adding a kernel version

1. add it to `pkgs/linux-rpi/linux-sources.nix`, newest first
2. add the firmware it pairs with to `overlays/firmware-sources.nix` — match
   `extra/git_hash` in the firmware tree against the kernel's rev
3. pair the two in `overlays/linux-and-firmware.nix`
4. `just test`

The `zfs` alias re-resolves by itself. A version can only be *removed* once
nothing below it is needed as a rung of that ladder.

## Advanced usage

Finer-grained control, for consumers that don't want `lib.nixosSystem`:

- implementation details in `lib/default.nix`, `lib/internal.nix`
- `nixos-raspberrypi.lib.int.nixosSystemRPi` instead of
  `nixos-raspberrypi.lib.nixosSystem`
- or plain `nixpkgs.lib.nixosSystem`, importing the modules by hand:

> [!IMPORTANT]
> With `nixpkgs.lib.nixosSystem` directly you **must** pass
> `nixos-raspberrypi` in `specialArgs`, so that board modules and profiles can
> find the flake:
>
> ```nix
> nixpkgs.lib.nixosSystem {
>   specialArgs = { inherit (inputs) nixos-raspberrypi; };
>   modules = [ ... ];
> };
> ```
>
> The `nixos-raspberrypi.lib.nixosSystem` helpers do this automatically.

```nix
imports = with nixos-raspberrypi.nixosModules; [
  # Required: overlays with kernel, firmware, vendor packages
  nixos-raspberrypi.lib.inject-overlays

  # The binary caches this flake's artefacts come from
  trusted-nix-caches

  # Optional: all RPi and RPi-optimised packages available as `pkgs.rpi`
  nixpkgs-rpi

  # Optional: optimised packages in the global scope — ffmpeg, kodi,
  # libcamera, vlc, etc. Causes lots of rebuilds, and these are *not* in the
  # cache: only kernels, firmware and profile closures are.
  nixos-raspberrypi.lib.inject-overlays-global
];
```

Individual packages can be taken from `packages.aarch64-linux` (the published,
cached set) or from `legacyPackages.aarch64-linux` (the whole RPi world, with
every overlay applied and nothing promised about the cache).

## Deployment

With `nixos-anywhere`, to a system running the installer image (uses
[disko](https://github.com/nix-community/disko/) to set the disks up):

```shell
nixos-anywhere --flake .#<system> root@<hostname>
```

or to an already running system:

```shell
nixos-rebuild switch --flake .#<system> --target-host root@<hostname>
```

## Design goals

This is essentially
[`boot.loader.raspberryPi`](https://search.nixos.org/options?channel=unstable&show=boot.loader.raspberryPi),
deprecated in nixpkgs, updated and improved upon:

- individually consumable modules and overlays for specific functions
- reuse of existing nixos/nixpkgs infrastructure and idiomatic approaches to
  the maximum extent possible
- integration with existing nixos system activation

Upstream keeps this deliberately unopinionated. This fork adds exactly one
opinion on top — the profiles — and keeps the rest of the machinery general.

### Historical background

Upstream grew out of the need to configure and extend
[tstat's raspberry-pi-nix](https://github.com/tstat/raspberry-pi-nix), which
proved virtually impossible to work with without reengineering the whole
thing; inability to use it non-interactively with `nixos-anywhere` was the
biggest concern. The `config.txt` generation module is still an adapted fork
of it.

Demo configurations for upstream are available at
<https://github.com/nvmd/nixos-raspberrypi-demo>.
