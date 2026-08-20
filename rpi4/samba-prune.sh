#!/bin/sh

# Buildroot's samba4 package installs the full binary set unconditionally --
# nmbd, winbindd, and the whole client toolset (smbclient, smbcacls, smbtar,
# ...) all land in the rootfs regardless of which BR2_PACKAGE_SAMBA4_* options
# are set (those only gate AD DC/ADS/smbtorture). The Universal Proxy app
# only ever execs smbd (the daemon we run under MuonTrap), smbpasswd (share
# user provisioning), and smbstatus (on-box debugging), so this prunes every
# other samba binary out of the shipped image. Binaries only: /usr/lib/samba
# is left alone because smbd dlopens modules from there at runtime.
# (usr/sbin/samba* was checked against a built rootfs -- only nmbd, smbd,
# winbindd live there, so there is nothing to glob-prune besides the
# explicit names below; smbd is never touched.)
#
# Idempotent (rm -f) and a safe no-op on targets without samba (x86_64/musl,
# where samba4 is never built -- see nerves_defconfig).
#
# Usage: samba-prune.sh TARGET_DIR

set -e

TARGET_DIR="$1"

removed=0

for f in \
  usr/sbin/nmbd \
  usr/sbin/winbindd \
  usr/bin/net \
  usr/bin/nmblookup \
  usr/bin/samba-log-parser \
  usr/bin/samba-regedit \
  usr/bin/smbcacls \
  usr/bin/smbclient \
  usr/bin/smbcontrol \
  usr/bin/smbcquotas \
  usr/bin/smbget \
  usr/bin/smbspool \
  usr/bin/smbtar \
  usr/bin/smbtree \
; do
  if [ -e "$TARGET_DIR/$f" ]; then
    rm -f "$TARGET_DIR/$f"
    removed=$((removed + 1))
  fi
done

echo "samba-prune: removed $removed file(s) under $TARGET_DIR"
