# Monorepo helpers for the custom Nerves systems.
#
# Canonical, shared inputs live under shared/:
#   shared/*.config            kernel config fragments
#   shared/firmware/brcm/*.hcd Broadcom BT controller firmware (all Pi chips)
#
# Each target subdir must be SELF-CONTAINED (its own copies), so that the main
# project can pull a single target via a git `sparse:` dep and so artifact
# checksums cover every build input. `make sync` materializes the shared
# inputs into each target; edit shared/, run `make sync`, commit.

# Targets that consume the shared inputs. Add new BT-capable forks here as you
# create them (rpi0 rpi0_2 rpi4 rpi5 ...). Non-BT targets need no entry.
TARGETS := rpi3

FW := $(wildcard shared/firmware/brcm/*.hcd)
CFG := $(wildcard shared/*.config)

.PHONY: sync check

## Copy shared kernel fragments + BT firmware into every target subdir.
sync:
	@for t in $(TARGETS); do \
	  for f in $(CFG); do \
	    install -m 0644 "$$f" "$$t/$$(basename $$f)"; \
	    echo "synced $$f -> $$t/"; \
	  done; \
	  mkdir -p "$$t/rootfs_overlay/lib/firmware/brcm"; \
	  for f in $(FW); do \
	    install -m 0644 "$$f" "$$t/rootfs_overlay/lib/firmware/brcm/$$(basename $$f)"; \
	    echo "synced $$f -> $$t/rootfs_overlay/lib/firmware/brcm/"; \
	  done; \
	done

## Fail if any target's copies have drifted from shared/ (use in CI).
check:
	@status=0; \
	for t in $(TARGETS); do \
	  for f in $(CFG); do \
	    cmp -s "$$f" "$$t/$$(basename $$f)" || { echo "DRIFT: $$t/$$(basename $$f)"; status=1; }; \
	  done; \
	  for f in $(FW); do \
	    cmp -s "$$f" "$$t/rootfs_overlay/lib/firmware/brcm/$$(basename $$f)" || { echo "DRIFT: $$t/.../$$(basename $$f)"; status=1; }; \
	  done; \
	done; \
	[ $$status -eq 0 ] && echo "ok: all targets in sync"; \
	exit $$status
