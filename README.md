# nerves_systems_universal_proxy

Custom Nerves systems for the Universal Proxy project — forks of the upstream
`nerves_system_*` systems with our additions (Bluetooth via **BlueZ + D-Bus**,
and USB-audio for USB DACs). One repo, one system per target subdirectory,
built in CI so consumers never need a local buildroot toolchain.

## Layout

```
.
├── shared/
│   ├── linux-bluetooth.config  # canonical kernel fragment (edit here → make sync)
│   └── users_table.txt         # canonical Buildroot users table (edit here → make sync)
├── rpi0/  rpi0_2/  rpi3/  rpi4/  rpi5/   # one Mix project per BT-capable target
│   ├── mix.exs                 #   artifact_sites → THIS repo's Releases
│   ├── nerves_defconfig        #   + BlueZ/D-Bus + firmware pkgs + kernel fragment ref
│   ├── linux-bluetooth.config  #   synced copy (referenced by the build)
│   └── users_table.txt         #   synced copy (referenced by the build)
├── Makefile                    # `make sync` / `make check`
└── .github/workflows/build.yml # matrix build → GitHub Releases
```

Targets covered: **rpi0** (Zero W), **rpi0_2** (Zero 2 W), **rpi3** (3B/3B+/CM3),
**rpi4** (4B/400/CM4), **rpi5**. `rpi`/`rpi2` have no onboard Bluetooth.

Each target subdir is a **self-contained Nerves system** (its own
`nerves_defconfig`, `fwup.conf`, overlay, and a local copy of any shared
fragment). Self-containment is required so the main project can pull a single
target via a git `sparse:` dep and so artifact checksums stay correct.

## The shared-fragment workflow

`shared/*.config` (kernel fragments), `shared/*.txt` (e.g. the Buildroot
users table, `shared/users_table.txt`), and `shared/*.sh` (shell helpers
like `shared/samba-prune.sh`) are the source of truth. Each target
references a **local copy** (e.g. `rpi3/linux-bluetooth.config`,
`rpi3/users_table.txt`) via `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` /
`BR2_ROOTFS_USERS_TABLES` (as `${NERVES_DEFCONFIG_DIR}/...`) in its
`nerves_defconfig`, while the .sh helper copies are invoked from each
target's `post-build.sh`. After editing anything under `shared/`:

```sh
make sync     # materialize copies into every target subdir
make check    # CI-friendly: fails if any copy drifted from shared/
git add -A && git commit
```

(We can't reference `../shared` directly from a target, because a `sparse:`
checkout only fetches that one subdir and the artifact checksum only covers
subdir-local files.)

## Controller firmware (via the nerves_system_br package — no vendored blobs)

Each target's `nerves_defconfig` enables **`BR2_PACKAGE_RPI_DISTRO_BLUEZ_FIRMWARE=y`**,
a nerves_system_br package that installs the Broadcom BT patchram set
(`BCM43430A1/B0`, `BCM4345C0/C5`) **plus the board-specific symlinks `btbcm`
requests first** (`BCM4345C0.raspberrypi,3-model-b-plus.hcd`, etc.) and the Pi
Zero 2 W **Synaptics** blobs — to `/lib/firmware/brcm/`. The stock image ships
only WiFi `brcmfmac` firmware and BlueZ (the host stack) carries no controller
firmware, so this package is what lets the kernel bring up the radio. (rpi5
already enabled it upstream.) No `.hcd` is committed to this repo — the package
fetches them at build time and gets the board mapping right for us.

## HDMI-CEC (rpi0_2, rpi3, rpi4, rpi5)

`shared/linux-cec.config` is a kernel fragment turning on the vc4 HDMI CEC
driver (`/dev/cecN`, one per HDMI port, via the kernel CEC API). Upstream
already has it on for rpi3/rpi4/rpi5 (Pi 5's HDMI is vc4 as well); rpi0_2
(Zero 2 W / 3A+) needs it. The driver only binds under the vc4 KMS display
path (`dtoverlay=vc4-kms-v3d` in `config.txt`). It's referenced from `rpi0_2`,
`rpi3`, `rpi4` and `rpi5` (`nerves_defconfig`, `package_files` in `mix.exs`).
No CEC userspace tool is shipped.

rpi3 was switched from the firmware display path to vc4 KMS for this
(`dtoverlay=vc4-kms-v3d`, `disable_fw_kms_setup=1`,
`display_auto_detect=1` replacing the firmware-only `rpi-ft5406`/
`rpi-backlight` overlays). Under KMS its HDMI audio moves from the bcm2835
card to a separate `vc4-hdmi` ALSA card; the headphone jack stays on bcm2835
(`dtparam=audio=on`). rpi0_2/rpi4/rpi5 were already on KMS.

`rpi`, `rpi0` and `rpi2` stay on the firmware display path and carry a synced
copy of the fragment without using it (no `/dev/cecN`); `x86_64` has no CEC.

## HDMI graphics memory: CMA, not gpu_mem (rpi0_2, rpi3, rpi4, rpi5)

Under vc4 KMS, HDMI graphics memory comes from Linux, not `gpu_mem`. `gpu_mem`
only feeds the firmware-side services (codecs, camera, the firmware audio
service), so it stays at 32 (16 would drop onboard audio; Pi 5 ignores it).
Where the buffers come from depends on the GPU generation:

- **Pi 0-3 (rpi0_2, rpi3): VC4.** The `vc4` driver runs both display and 3D,
  and allocates every GPU buffer (framebuffers, scanout, GL render buffers)
  contiguously from the CMA pool (`drm_gem_dma`). CMA caps how much graphics
  can run, so these targets raise it.
- **Pi 4/5 (rpi4, rpi5): V3D.** 3D is the separate `v3d` driver. It has its
  own MMU and allocates render buffers from shmem (ordinary pages), so a larger
  CMA pool doesn't give GL more room. CMA only backs the display side (`vc4`
  dumb/scanout buffers). On Pi 5 the HVS also sits behind an IOMMU
  (`iommus = <&iommu4>` in `bcm2712.dtsi`). Their defaults stay as they are.
  Raise them only after a graphics buffer allocation has actually failed
  because CMA ran out: the kernel logs `__cma_alloc: ...: alloc failed,
  req-size: ...` and DRM buffer creation returns `-ENOMEM`. A low `CmaFree`
  is not evidence on its own, because movable userspace and page-cache pages
  borrow CMA and are migrated out when graphics needs the space. A bigger pool
  takes memory away from unmovable kernel allocations.

The size is the `cma-*` parameter of `dtoverlay=vc4-kms-v3d`, which the
firmware maps to a per-SoC overlay (`overlay_map.dts`). The defaults in the
pinned kernel (`stable_20260527`) match the firmware `.dtbo`s we ship
(`1.20260521`):

- `vc4-kms-v3d` (bcm2835/2710): 256MB, from `cma-overlay.dts`
- `vc4-kms-v3d-pi4`: overrides it to 508MB (`(512-4)*1024*1024`)
- `vc4-kms-v3d-pi5`: overrides it to 64MB

Without the overlay, the base device trees reserve 64MB. CMA pages aren't lost
while display or graphics leaves them idle: the kernel lends them to movable
allocations (userspace, page cache). Unmovable kernel allocations can't use
them.

| Target | RAM         | `config.txt`                    | CMA   |
|--------|-------------|---------------------------------|-------|
| rpi0_2 | 512MB       | `dtoverlay=vc4-kms-v3d,cma-192` | 192MB |
| rpi3   | 1GB         | `dtoverlay=vc4-kms-v3d,cma-256` | 256MB |
| rpi4   | 1GB and up  | `dtoverlay=vc4-kms-v3d`         | 508MB (overlay default) |
| rpi5   | 1GB and up  | `dtoverlay=vc4-kms-v3d`         | 64MB (overlay default) |

rpi0_2 stays below the 256MB default because that much of a 512MB board would
leave little for unmovable kernel memory. `CmaTotal` in `/proc/meminfo` shows
the size of the reservation a board actually got.

## Adding another target

Same recipe as the existing five:
1. Copy the upstream system into a new subdir (drop `.git`/`hex_metadata.config`).
2. `mix.exs`: `@github_organization "bbangert"`, add `@releases_repo` +
   `{:github_releases, @releases_repo}` in `artifact_sites`, add
   `"linux-bluetooth.config"` to `package_files()`, set `VERSION` to `0.1.0`.
3. `nerves_defconfig`: add the `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` line +
   `BR2_PACKAGE_DBUS=y` / `BR2_PACKAGE_BLUEZ5_UTILS=y` /
   `BR2_PACKAGE_RPI_DISTRO_BLUEZ_FIRMWARE=y`.
4. Add it to `TARGETS` (Makefile) + `matrix.target` (build.yml), then `make sync`.

## How CI publishes, and how the project consumes it

- Push a tag `vX.Y.Z` → the `build` job compiles each target's artifact and
  uploads it to that tag's **GitHub Release**.
- In `universal_proxy`'s `mix.exs`, point the customized target(s) at this repo
  (a git dep with `sparse:` selects the subdir; `override: true` replaces the
  upstream hex system):

  ```elixir
  {:nerves_system_rpi3, github: "bbangert/nerves_systems_universal_proxy",
     sparse: "rpi3", tag: "v0.1.0", runtime: false, targets: :rpi3, override: true},
  ```

- `mix deps.get && mix deps.compile` then **downloads the prebuilt artifact**
  (matched by app-name + checksum from `artifact_sites`) into `~/.nerves` — no
  local buildroot. Leave non-customized targets on their upstream hex systems.

### Caveats
- **Host arch:** artifacts are per-host. CI builds the **linux/x86_64**
  artifact — consume it from a linux/x86_64 host (or build firmware in CI too).
  An Apple-Silicon Mac can't use the x86_64 artifact and would fall back to a
  (failing, toolchain-less) local build.
- **Checksum discipline:** every change to a system's source must be rebuilt &
  republished (new tag) or `mix deps.compile` won't find a matching artifact
  and will try to build locally. Pin by `tag:`, not `branch:`.
- **Private repo:** consuming Release assets from a private repo needs a token.

## Not in this repo: the `bluetoothd` startup + D-Bus client

Bringing up `dbus-daemon` + `bluetoothd` at runtime, and talking to
`org.bluez` (via the `rebus` Elixir D-Bus client), lives in the **application**
(`universal_proxy`), not in the system image — because Nerves uses `erlinit`,
not systemd. Plan: a small supervisor that launches both daemons (e.g. via
`MuonTrap.Daemon`) with writable state on `/root` (machine-id,
`/var/lib/bluetooth`), then the BT supervision tree connects to the system bus.
