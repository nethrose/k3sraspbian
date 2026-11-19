#!/bin/sh
# Write patch-state metrics for the node_exporter textfile collector. Runs from
# APT::Update::Post-Invoke-Success, from DPkg::Post-Invoke (see 99node-patch-metrics),
# and from the hourly node-patch-metrics.timer, so the metrics stay fresh even on a day
# with no apt activity at all.
#
# Metric names are exact: the cluster-side alerts (k3s-gitops) match on them.
#
# The *_DIR / *_FILE / *_LOG env vars below default to the real paths; they exist only
# so tests can point this script at fixture directories without changing its behavior on
# a real node.
set -u

textfile_dir="${NODE_PATCH_METRICS_TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
apt_lists_dir="${NODE_PATCH_METRICS_APT_LISTS_DIR:-/var/lib/apt/lists}"
uu_log="${NODE_PATCH_METRICS_UU_LOG:-/var/log/unattended-upgrades/unattended-upgrades.log}"
modules_dir="${NODE_REBOOT_REQUIRED_MODULES_DIR:-/lib/modules}"
proc_dir="${NODE_REBOOT_REQUIRED_PROC_DIR:-/proc}"
reboot_flag="${NODE_REBOOT_REQUIRED_FLAG:-/run/reboot-required}"
reboot_info="${NODE_REBOOT_REQUIRED_INFO:-/run/reboot-required.pkgs}"
running="${NODE_REBOOT_REQUIRED_RUNNING_KERNEL:-$(uname -r)}"
out="${textfile_dir}/node_patch.prom"
tmp="${out}.$$.tmp"

# apt-get -s (simulate) needs no changes applied, only readable lists, and is itself
# read-only, so it is safe to run from a metrics hook. NODE_PATCH_METRICS_SIM_OUTPUT lets
# tests substitute fixture "Inst ..." lines instead of running real apt-get.
sim="${NODE_PATCH_METRICS_SIM_OUTPUT:-$(apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null || true)}"

count_origin() {
  # Count "Inst" lines whose candidate comes from the given origin label.
  printf '%s\n' "$sim" | grep -c "^Inst .*$1:" 2>/dev/null || true
}

pending_debian_security=$(count_origin "Debian-Security")
pending_debian=$(count_origin "Debian")
pending_rpi=$(count_origin "Raspberry Pi Foundation")

# newest */InRelease mtime across the configured lists, 0 if none exist yet
newest_list_epoch=0
for f in "${apt_lists_dir}"/*InRelease; do
  [ -e "$f" ] || continue
  mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  [ "$mtime" -gt "$newest_list_epoch" ] && newest_list_epoch=$mtime
done
now=$(date +%s)
if [ "$newest_list_epoch" -gt 0 ]; then
  lists_age=$((now - newest_list_epoch))
else
  lists_age=-1
fi

# Last "Starting unattended upgrades script" block: its timestamp, and whether any
# ERROR line appears from there to the end of the log.
uu_timestamp=0
uu_success=0
if [ -r "$uu_log" ]; then
  start_line=$(grep -n 'Starting unattended upgrades script' "$uu_log" | tail -n1 | cut -d: -f1 || true)
  if [ -n "${start_line:-}" ]; then
    start_date=$(sed -n "${start_line}p" "$uu_log" | cut -d' ' -f1-2 | tr ',' '.')
    uu_timestamp=$(date -d "$start_date" +%s 2>/dev/null || echo 0)
    if tail -n "+${start_line}" "$uu_log" | grep -q 'ERROR'; then
      uu_success=0
    else
      uu_success=1
    fi
  fi
fi

dpkg_audit_problems=$(dpkg --audit 2>/dev/null | wc -l | tr -d ' ')

# Same tests as node-reboot-required, re-derived fresh rather than read from its flag
# file, so this metric reflects the current state even if the hook hasn't fired yet.
flavour=${running##*+rpt-}
# shellcheck disable=SC2010 # module directory names are kernel version strings, not arbitrary
newest_kernel=$(ls -1 "$modules_dir" | grep -- "+rpt-${flavour}\$" | sort -V | tail -n1)
kernel_pending=0
[ -n "$newest_kernel" ] && [ "$newest_kernel" != "$running" ] && kernel_pending=1

hostns=$(readlink "${proc_dir}/1/ns/mnt" 2>/dev/null || true)
stale_processes=0
for p in "${proc_dir}"/[0-9]*; do
  [ -e "$p" ] || continue
  [ "$(readlink "$p/ns/mnt" 2>/dev/null)" = "$hostns" ] || continue
  grep -qE ' /(usr/)?lib/[^ ]*\.so[^ ]* \(deleted\)$' "$p/maps" 2>/dev/null && stale_processes=$((stale_processes + 1))
done

reboot_required=0
reboot_reason=""
if [ -e "$reboot_flag" ]; then
  reboot_required=1
  [ -r "$reboot_info" ] && reboot_reason=$(tr '\n' ' ' < "$reboot_info" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/ *$//')
fi
[ "$kernel_pending" -eq 1 ] || [ "$stale_processes" -gt 0 ] && reboot_required=1

mkdir -p "$textfile_dir"
{
  echo "# HELP node_apt_upgrades_pending Pending apt upgrades by origin."
  echo "# TYPE node_apt_upgrades_pending gauge"
  echo "node_apt_upgrades_pending{origin=\"Debian-Security\"} ${pending_debian_security}"
  echo "node_apt_upgrades_pending{origin=\"Debian\"} ${pending_debian}"
  echo "node_apt_upgrades_pending{origin=\"Raspberry Pi Foundation\"} ${pending_rpi}"

  echo "# HELP node_apt_lists_age_seconds Age of the newest apt list, or -1 if none exist."
  echo "# TYPE node_apt_lists_age_seconds gauge"
  echo "node_apt_lists_age_seconds ${lists_age}"

  echo "# HELP node_unattended_upgrades_last_run_timestamp_seconds Start time of the last unattended-upgrades run."
  echo "# TYPE node_unattended_upgrades_last_run_timestamp_seconds gauge"
  echo "node_unattended_upgrades_last_run_timestamp_seconds ${uu_timestamp}"

  echo "# HELP node_unattended_upgrades_last_run_success Whether the last unattended-upgrades run logged no ERROR lines."
  echo "# TYPE node_unattended_upgrades_last_run_success gauge"
  echo "node_unattended_upgrades_last_run_success ${uu_success}"

  echo "# HELP node_dpkg_audit_problems Line count of dpkg --audit (half-installed packages)."
  echo "# TYPE node_dpkg_audit_problems gauge"
  echo "node_dpkg_audit_problems ${dpkg_audit_problems}"

  echo "# HELP node_reboot_required Whether a reboot is flagged as required."
  echo "# TYPE node_reboot_required gauge"
  echo "node_reboot_required ${reboot_required}"
  echo "# HELP node_reboot_required_info Reason a reboot is flagged as required."
  echo "# TYPE node_reboot_required_info gauge"
  echo "node_reboot_required_info{reason=\"${reboot_reason}\"} ${reboot_required}"

  echo "# HELP node_kernel_pending Whether a newer kernel is installed than the one running."
  echo "# TYPE node_kernel_pending gauge"
  echo "node_kernel_pending ${kernel_pending}"

  echo "# HELP node_stale_library_processes Host processes still mapping a library apt has replaced."
  echo "# TYPE node_stale_library_processes gauge"
  echo "node_stale_library_processes ${stale_processes}"
} > "$tmp"
mv "$tmp" "$out"
