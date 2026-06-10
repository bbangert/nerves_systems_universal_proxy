# nerves_systems_universal_proxy

Custom Nerves systems for the Universal Proxy project — forks of the upstream
`nerves_system_*` systems with our additions (Bluetooth via **BlueZ + D-Bus**,
and USB-audio for USB DACs). One repo, one system per target subdirectory,
built in CI so consumers never need a local buildroot toolchain.

> **Replace `REPLACE_ORG`** in each `*/mix.exs` (`@github_organization` /
> `@releases_repo`) with your GitHub org/user before pushing.

## Layout

```
.
├── shared/                     # canonical kernel config fragments (edit here)
│   └── linux-bluetooth.config  #   → `make sync` copies into each target
├── rpi3/                       # custom nerves_system_rpi3 (one Mix project)
│   ├── mix.exs                 #   artifact_sites → THIS repo's Releases
│   ├── nerves_defconfig        #   + BlueZ/D-Bus pkgs, + kernel fragment ref
│   ├── linux-bluetooth.config  #   synced copy (referenced by the build)
│   └── rootfs_overlay/lib/firmware/brcm/   # drop BCM4345C0.hcd here (see its README)
├── Makefile                    # `make sync` / `make check`
└── .github/workflows/build.yml # matrix build → GitHub Releases
```

Each target subdir is a **self-contained Nerves system** (its own
`nerves_defconfig`, `fwup.conf`, overlay, and a local copy of any shared
fragment). Self-containment is required so the main project can pull a single
target via a git `sparse:` dep and so artifact checksums stay correct.

## The shared-fragment workflow

`shared/*.config` are the source of truth. Each target references a **local
copy** (e.g. `rpi3/linux-bluetooth.config`) via
`BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` in its `nerves_defconfig`. After
editing anything under `shared/`:

```sh
make sync     # materialize copies into every target subdir
make check    # CI-friendly: fails if any copy drifted from shared/
git add -A && git commit
```

(We can't reference `../shared` directly from a target, because a `sparse:`
checkout only fetches that one subdir and the artifact checksum only covers
subdir-local files.)

## Controller firmware (vendored, all BT-capable Pis)

`shared/firmware/brcm/*.hcd` holds the Broadcom BT patchram blobs for every
BT-capable Raspberry Pi (from RPi-Distro/bluez-firmware). `make sync` copies
the **whole set** into each target's `rootfs_overlay/lib/firmware/brcm/`; the
kernel `btbcm` driver loads the one matching the detected chip, so there's no
per-board mapping to get wrong. The stock image ships no `.hcd`, and BlueZ (the
host stack) carries no controller firmware — see `shared/firmware/README.md`
for the chip → board → target table.

## Adding another target (e.g. rpi4, rpi0_2)

1. Copy the upstream system source into a new subdir:
   `cp -r <deps>/nerves_system_rpi4 ./rpi4` (drop `hex_metadata.config`).
2. In `rpi4/mix.exs`: set `@github_organization`/`@releases_repo` (as in rpi3),
   add `"linux-bluetooth.config"` to `package_files()`.
3. In `rpi4/nerves_defconfig`: add the `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`
   line + the BlueZ/D-Bus package block (copy from `rpi3/nerves_defconfig`).
4. Add `rpi4` to `TARGETS` in the `Makefile` and to the `matrix.target` list in
   `.github/workflows/build.yml`, then `make sync` — the kernel fragment **and**
   the full BT firmware set are copied in automatically (no per-board blob to
   pick; `btbcm` loads the right `.hcd` for the detected chip).

## How CI publishes, and how the project consumes it

- Push a tag `vX.Y.Z` → the `build` job compiles each target's artifact and
  uploads it to that tag's **GitHub Release**.
- In `universal_proxy`'s `mix.exs`, point the customized target(s) at this repo
  (a git dep with `sparse:` selects the subdir; `override: true` replaces the
  upstream hex system):

  ```elixir
  {:nerves_system_rpi3, github: "REPLACE_ORG/nerves_systems_universal_proxy",
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
