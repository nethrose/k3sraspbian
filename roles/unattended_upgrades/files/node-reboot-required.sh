#!/bin/sh
# Flag a reboot when the newest installed kernel is not the running one, or when a host
# (not container) process still maps a library apt has replaced.
#
# Pi OS kernel packages never create /run/reboot-required (only dbus.postinst does), so
# this runs from a DPkg::Post-Invoke hook (see 99node-reboot-required) to fill that gap.
#
# The *_DIR / *_FLAG / *_KERNEL env vars below default to the real paths; they exist only
# so tests can point this script at fixture directories without changing its behavior on
# a real node.
set -u

modules_dir="${NODE_REBOOT_REQUIRED_MODULES_DIR:-/lib/modules}"
proc_dir="${NODE_REBOOT_REQUIRED_PROC_DIR:-/proc}"
reboot_flag="${NODE_REBOOT_REQUIRED_FLAG:-/run/reboot-required}"
reboot_info="${NODE_REBOOT_REQUIRED_INFO:-/run/reboot-required.pkgs}"
running="${NODE_REBOOT_REQUIRED_RUNNING_KERNEL:-$(uname -r)}"

flavour=${running##*+rpt-}
# shellcheck disable=SC2010 # module directory names are kernel version strings, not arbitrary
newest=$(ls -1 "$modules_dir" | grep -- "+rpt-${flavour}\$" | sort -V | tail -n1)
reason=""
[ -n "$newest" ] && [ "$newest" != "$running" ] && reason="kernel ${running} -> ${newest}"

hostns=$(readlink "${proc_dir}/1/ns/mnt" 2>/dev/null || true)
stale=0
for p in "${proc_dir}"/[0-9]*; do
  [ -e "$p" ] || continue
  [ "$(readlink "$p/ns/mnt" 2>/dev/null)" = "$hostns" ] || continue
  grep -qE ' /(usr/)?lib/[^ ]*\.so[^ ]* \(deleted\)$' "$p/maps" 2>/dev/null && stale=$((stale + 1))
done
[ "$stale" -gt 0 ] && reason="${reason:+$reason; }${stale} host processes map replaced libraries"

if [ -n "$reason" ]; then
  echo "$reason" > "$reboot_info"
  : > "$reboot_flag"
fi
