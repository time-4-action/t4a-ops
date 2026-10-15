#!/usr/bin/env bash
#
# t4a-ops-deploy — install this repo's server files on t4a-t2. CI runs it on
# every push to main; see docs/runbooks/ops-deploy.md.
#
# Usage (as root):
#   t4a-ops-deploy <commit-sha> < scripts.tar.gz   # tar.gz of the repo's scripts/ dir
#   t4a-ops-deploy --status
#
# Installed at /usr/local/sbin/t4a-ops-deploy (root:root 0755). The deploy user
# may run only this command through sudo (/etc/sudoers.d/t4a-ops-deploy).
#
# Idempotent: installs every file in MANIFEST, verifies the result and, if
# verification fails, puts the previous files back. Never touches
# /etc/t4a-backup.env and never enables or disables a timer.

set -euo pipefail

STATE=/var/lib/t4a-ops

# <path in repo> <installed path> <mode>
MANIFEST=(
  "scripts/backup.sh                              /usr/local/bin/t4a-backup.sh                       0750"
  "scripts/systemd/t4a-backup.service             /etc/systemd/system/t4a-backup.service             0644"
  "scripts/systemd/t4a-backup.timer               /etc/systemd/system/t4a-backup.timer               0644"
  "scripts/systemd/t4a-backup-maintenance.service /etc/systemd/system/t4a-backup-maintenance.service 0644"
  "scripts/systemd/t4a-backup-maintenance.timer   /etc/systemd/system/t4a-backup-maintenance.timer   0644"
  "scripts/deploy/t4a-ops-deploy.sh               /usr/local/sbin/t4a-ops-deploy                     0755"
)
TIMERS=(t4a-backup.timer t4a-backup-maintenance.timer)

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }

if [[ "${1:-}" == --status ]]; then
  cat "$STATE/deployed" 2>/dev/null || echo "never deployed"
  systemctl list-timers 't4a-backup*' --no-pager
  exit 0
fi

SHA="${1:-}"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "usage: $0 <commit-sha> < scripts.tar.gz | --status" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }

mkdir -p "$STATE"
# One deploy at a time.
exec 9>"$STATE/lock"
flock -w 300 9 || { echo "another deploy holds $STATE/lock" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/new" "$WORK/old"

tar -xzf - -C "$WORK/new" --no-same-owner

# Check the new files before anything on the server changes.
for entry in "${MANIFEST[@]}"; do
  read -r src _ _ <<<"$entry"
  [[ -f "$WORK/new/$src" ]] || { echo "archive is missing $src" >&2; exit 1; }
  if [[ "$src" == *.sh ]]; then
    bash -n "$WORK/new/$src" || { echo "$src does not parse" >&2; exit 1; }
  fi
done

ACTIVE_TIMERS=()
for t in "${TIMERS[@]}"; do
  systemctl is-active --quiet "$t" && ACTIVE_TIMERS+=("$t")
done

# Save what is installed now; a file that did not exist is marked absent.
CHANGED=()
for i in "${!MANIFEST[@]}"; do
  read -r src dest _ <<<"${MANIFEST[$i]}"
  if [[ -e "$dest" ]]; then
    cp -p "$dest" "$WORK/old/$i"
  else
    touch "$WORK/old/$i.absent"
  fi
  cmp -s "$WORK/new/$src" "$dest" || CHANGED+=("$dest")
done

# Write to a temp file and rename over the target: a backup running right now
# keeps reading its old copy of the script instead of a half-written one.
put() {
  local src=$1 dest=$2 mode=$3
  install -m "$mode" -o root -g root "$src" "$dest.t4a-ops-new"
  mv -f "$dest.t4a-ops-new" "$dest"
}

# Timers only pick up a changed schedule when restarted. Inactive timers stay
# inactive: enabling them is a manual step (docs/runbooks/backup-restore.md).
reload() {
  systemctl daemon-reload
  local t
  for t in "${ACTIVE_TIMERS[@]}"; do
    if printf '%s\n' "${CHANGED[@]}" | grep -qx "/etc/systemd/system/$t"; then
      systemctl restart "$t"
    fi
  done
}

verify() {
  local t
  bash -n /usr/local/bin/t4a-backup.sh || return 1
  systemd-analyze verify /etc/systemd/system/t4a-backup*.service /etc/systemd/system/t4a-backup*.timer || return 1
  for t in "${ACTIVE_TIMERS[@]}"; do
    systemctl is-active --quiet "$t" || { echo "$t is no longer active" >&2; return 1; }
  done
  # Same config and tools the nightly run needs. Before the first-time setup
  # there is no config yet, and nothing to check.
  if [[ -f /etc/t4a-backup.env ]]; then
    /usr/local/bin/t4a-backup.sh check || return 1
  fi
}

rollback() {
  log "verification failed, restoring the previous files"
  local i src dest mode
  for i in "${!MANIFEST[@]}"; do
    read -r src dest mode <<<"${MANIFEST[$i]}"
    if [[ -e "$WORK/old/$i.absent" ]]; then
      rm -f "$dest"
    else
      put "$WORK/old/$i" "$dest" "$mode"
    fi
  done
  reload
  verify || log "the previous files do not verify either"
}

log "deploying $SHA (changed: ${CHANGED[*]:-nothing})"
for entry in "${MANIFEST[@]}"; do
  read -r src dest mode <<<"$entry"
  put "$WORK/new/$src" "$dest" "$mode"
done
reload

if ! verify; then
  rollback
  exit 1
fi

echo "$SHA $(date -Is)" >"$STATE/deployed"
log "deployed $SHA"
systemctl list-timers 't4a-backup*' --no-pager
