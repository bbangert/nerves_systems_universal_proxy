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
# Second job: samba4's waf install unconditionally puts ~44 public runtime
# libs (libsamba-errors, libndr*, libsmbconf, libwbclient, ...) in
# usr/lib64/, never usr/lib/. On 64-bit targets usr/lib64 is a symlink to
# usr/lib so this is invisible; on 32-bit targets (rpi, rpi0, rpi2, rpi3 --
# confirmed via built rootfs.squashfs) usr/lib64 is a REAL directory the
# ARM32 loader never searches, so every samba binary failed to start on
# hardware: "smbpasswd: error while loading shared libraries:
# libsamba-errors.so.1: cannot open shared object file" (rpi3 HW validation,
# 2026-08-20). This merges a real usr/lib64 into usr/lib and replaces it
# with a usr/lib64 -> lib symlink, matching the 64-bit layout. Idempotent
# (symlink case is a no-op) and a no-op when usr/lib64 doesn't exist at all.
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

LIB64="$TARGET_DIR/usr/lib64"
LIB="$TARGET_DIR/usr/lib"

if [ -d "$LIB64" ] && [ ! -L "$LIB64" ]; then
  merged=0
  for entry in "$LIB64"/* "$LIB64"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    base=$(basename "$entry")
    if [ -e "$LIB/$base" ] || [ -L "$LIB/$base" ]; then
      echo "samba-prune: ERROR: $LIB/$base already exists, refusing to clobber while merging $LIB64" >&2
      exit 1
    fi
    mv "$entry" "$LIB/"
    merged=$((merged + 1))
  done
  rmdir "$LIB64"
  ln -s lib "$LIB64"
  echo "samba-prune: merged $merged waf-misplaced lib64 entries into $LIB and replaced $LIB64 with a lib64 -> lib symlink"
fi
