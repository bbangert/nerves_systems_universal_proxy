# Broadcom Bluetooth controller firmware (Raspberry Pi)

`brcm/*.hcd` are the controller patchram blobs the kernel `btbcm` driver loads
into the onboard BT silicon at init. They come from the official
[RPi-Distro/bluez-firmware](https://github.com/RPi-Distro/bluez-firmware)
(`debian/firmware/broadcom/`, branch `pios/trixie`). The stock Nerves rpi
images ship only WiFi `brcmfmac` blobs — no `.hcd` — and BlueZ (the host stack)
does not provide controller firmware, so we vendor it here.

`make sync` copies the **whole set** into every BT-capable target's
`rootfs_overlay/lib/firmware/brcm/`. That's intentional and matches Raspberry
Pi OS: `btbcm` requests the blob by the **chip's own reported name**, so it can
only ever load the correct one — extra files are harmless (~190 KB total) and
there is zero risk of loading the wrong firmware.

## Chip → board → Nerves target

| `.hcd` | Broadcom chip | Boards | Nerves target(s) |
|--------|---------------|--------|------------------|
| `BCM43430A1.hcd` | BCM43438 | Pi 3B (orig), Pi Zero W, CM3 | `rpi0`, `rpi3` |
| `BCM43430B0.hcd` | (RP3A0) | Pi Zero 2 W | `rpi0_2` (and `rpi3`'s zero-2-w DT) |
| `BCM4345C0.hcd` | BCM4345C0 (LMP 0x6119) | Pi 3B+, 3A+ | `rpi3` |
| `BCM4345C5.hcd` | BCM4345C5 (LMP 0x6606) | Pi 4, 400, CM4, Pi 5 | `rpi4`, `rpi5` |

Non-BT Nerves targets (`rpi`, `rpi2`) need none of these.

> If a new board needs a chip not listed here, add its `.hcd` from
> RPi-Distro/bluez-firmware and re-run `make sync`. `BCM4343A2.hcd` was
> deliberately omitted — no supported Nerves rpi target uses it.
