#!/usr/bin/env bash
#
# T4A backup — restic -> Hetzner Storage Box (SFTP).
#
# Usage:
#   backup.sh [all|mariadb|wordpress|hub|mongodb|configs|maintenance|check]
#
# `check` only validates the config and the tools the backup needs; the deploy
# runs it after every install (scripts/deploy/t4a-ops-deploy.sh).
#
# `all` runs every step even when one fails, then exits 1 if any did, so one
# broken step cannot silently skip the rest (the retired n8n step did that
# from 2026-06-15 to 2026-10-25).
#
# Config file: /etc/t4a-backup.env (see backup.env.example)
# Runs as root. Depends on restic, mariadb-dump, docker, and ~/.ssh/config alias.

set -euo pipefail

CONFIG="${T4A_BACKUP_CONFIG:-/etc/t4a-backup.env}"
[[ -f "$CONFIG" ]] || { echo "missing config: $CONFIG" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }

validate_config() {
  local ok=1
  local required_vars=(RESTIC_REPOSITORY RESTIC_PASSWORD_FILE BACKUP_HOST MONGO_URI)
  local required_arrays=(BACKUP_PATHS_WORDPRESS BACKUP_PATHS_CONFIGS)

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      echo "config error: $var is not set in $CONFIG" >&2
      ok=0
    fi
  done

  for arr in "${required_arrays[@]}"; do
    # nameref trick to check array length without eval
    declare -n _arr="$arr" 2>/dev/null
    if [[ ${#_arr[@]} -eq 0 ]]; then
      echo "config error: $arr is empty or not set in $CONFIG" >&2
      ok=0
    fi
    unset -n _arr
  done

  [[ $ok -eq 1 ]] || { echo "fix $CONFIG and re-run" >&2; exit 1; }
}

backup_mariadb() {
  log "dump MariaDB -> restic (tag=mariadb)"
  # --single-transaction: consistent snapshot on InnoDB without table locks.
  # --quick: stream row-by-row so RAM stays flat on big tables.
  mariadb-dump \
    --defaults-file=/root/.my.cnf \
    --single-transaction \
    --quick \
    --routines --triggers --events \
    --all-databases \
  | restic backup --stdin \
      --stdin-filename "all-databases.sql" \
      --tag mariadb \
      --host "$BACKUP_HOST"
}

backup_wordpress() {
  log "backup WordPress files -> restic (tag=wordpress)"
  restic backup \
    --tag wordpress \
    --host "$BACKUP_HOST" \
    --exclude '*/wp-content/cache' \
    --exclude '*/wp-content/upgrade' \
    --exclude '*/wp-content/uploads/cache' \
    --exclude '*/wp-content/*/cache' \
    --exclude '*.log' \
    "${BACKUP_PATHS_WORDPRESS[@]}"
}

backup_configs() {
  log "backup configs -> restic (tag=configs)"
  restic backup \
    --tag configs \
    --host "$BACKUP_HOST" \
    "${BACKUP_PATHS_CONFIGS[@]}"
}

# dump_postgres CONTAINER FILENAME TAG
# pg_dump runs inside the container so we do not need a postgres client
# on the host. PGPASSWORD + -U come from the container's own env.
# --clean --if-exists makes the dump idempotent on restore.
dump_postgres() {
  docker exec "$1" \
    sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --clean --if-exists -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  | restic backup --stdin \
      --stdin-filename "$2" \
      --tag "$3" \
      --host "$BACKUP_HOST"
}

backup_hub() {
  if [[ -z "${HUB_POSTGRES_CONTAINER:-}" ]]; then
    log "HUB_POSTGRES_CONTAINER not set, skipping Recharge Hub"
    return 0
  fi
  log "dump Recharge Hub PostgreSQL -> restic (tag=hub-postgres)"
  dump_postgres "$HUB_POSTGRES_CONTAINER" recharge-hub.sql hub-postgres
}

backup_mongodb() {
  log "dump MongoDB -> restic (tag=mongodb)"
  # mongodump --archive streams a binary archive; pipe directly into restic.
  # MONGO_URI must include credentials: mongodb://user:pass@localhost:27017
  mongodump --uri="$MONGO_URI" --archive \
  | restic backup --stdin \
      --stdin-filename "mongodb.archive" \
      --tag mongodb \
      --host "$BACKUP_HOST"
}

check_tools() {
  local ok=1 cmd
  for cmd in restic mariadb-dump mongodump docker; do
    command -v "$cmd" >/dev/null || { echo "check: $cmd is not installed" >&2; ok=0; }
  done
  [[ -f "$RESTIC_PASSWORD_FILE" ]] || { echo "check: $RESTIC_PASSWORD_FILE does not exist" >&2; ok=0; }
  [[ $ok -eq 1 ]] || exit 1
  log "config and tools ok"
}

forget_old() {
  log "forget old snapshots per retention policy"
  restic forget \
    --group-by 'host,tags' \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6
}

maintenance() {
  log "prune unreferenced data + integrity check (sampled)"
  restic prune
  restic check --read-data-subset=10%
}

# run_step FN: runs one backup step, records it in $failed when it fails.
run_step() {
  "$1" || { log "FAILED: $1"; failed+=("$1"); }
}

main() {
  validate_config
  local target="${1:-all}"
  case "$target" in
    mariadb)     backup_mariadb ;;
    wordpress)   backup_wordpress ;;
    configs)     backup_configs ;;
    hub)         backup_hub ;;
    mongodb)     backup_mongodb ;;
    all)
      local failed=() step
      for step in backup_mariadb backup_wordpress backup_hub backup_mongodb backup_configs forget_old; do
        run_step "$step"
      done
      if [[ ${#failed[@]} -gt 0 ]]; then
        log "done (all) with failures: ${failed[*]}"
        exit 1
      fi
      ;;
    maintenance) maintenance ;;
    check)       check_tools; return ;;
    *) echo "usage: $0 [all|mariadb|wordpress|hub|mongodb|configs|maintenance|check]" >&2; exit 2 ;;
  esac
  log "done ($target)"
}

main "$@"
