#!/bin/sh

# The only Buildroot package that ships cec-ctl is libv4l with
# BR2_PACKAGE_LIBV4L_UTILS, and that installs the entire v4l-utils toolset
# (v4l2-ctl, media-ctl, cec-follower, cec-compliance, ir-*, rds-ctl, the DVB
# tools, ...) plus the libv4l runtime libs, udev keymaps and config under
# /etc. The Universal Proxy app only ever execs cec-ctl, which is statically
# linked against v4l-utils' libcecutil and needs nothing beyond glibc, so this
# strips everything else libv4l installed out of the shipped image.
#
# It works from Buildroot's per-package install manifest
# ($BUILD_DIR/packages-file-list.txt, "<pkg>,./<path>" per line), which
# target-finalize writes just before running the post-build scripts, so the
# prune tracks whatever a future v4l-utils bump installs instead of a
# hard-coded name list. Idempotent, and a no-op on targets that don't build
# libv4l (the manifest simply has no libv4l rows).
#
# Usage: cec-prune.sh TARGET_DIR   (BUILD_DIR comes from the Buildroot env)

set -e

TARGET_DIR="$1"
MANIFEST="${BUILD_DIR:?cec-prune: BUILD_DIR not set (run from a Buildroot post-build hook)}/packages-file-list.txt"
KEEP="./usr/bin/cec-ctl"

if [ ! -f "$MANIFEST" ]; then
  echo "cec-prune: ERROR: $MANIFEST missing" >&2
  exit 1
fi

if ! grep -q '^libv4l,' "$MANIFEST"; then
  echo "cec-prune: libv4l not built for this target; nothing to prune"
  exit 0
fi

removed=0
dirs=""
for p in $(grep '^libv4l,' "$MANIFEST" | cut -d, -f2-); do
  [ "$p" = "$KEEP" ] && continue
  f="$TARGET_DIR/${p#./}"
  if [ -f "$f" ] || [ -L "$f" ]; then
    rm -f "$f"
    removed=$((removed + 1))
    dirs="$dirs $(dirname "$f")"
  fi
done

# Drop directories the prune emptied (e.g. usr/lib/libv4l plugin dir,
# lib/udev/rc_keymaps). Deepest first; rmdir refuses non-empty dirs, so
# shared parents like usr/lib are never touched.
for d in $(printf '%s\n' $dirs | sort -ur); do
  while [ "$d" != "$TARGET_DIR" ] && [ -d "$d" ] && rmdir "$d" 2>/dev/null; do
    d=$(dirname "$d")
  done
done

if [ ! -x "$TARGET_DIR/usr/bin/cec-ctl" ]; then
  echo "cec-prune: ERROR: $TARGET_DIR/usr/bin/cec-ctl is missing after prune" >&2
  exit 1
fi

echo "cec-prune: removed $removed libv4l file(s) under $TARGET_DIR, kept usr/bin/cec-ctl"
