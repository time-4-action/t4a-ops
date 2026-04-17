#!/usr/bin/env bash
#
# T4A backup — restic -> Hetzner Storage Box (SFTP).
#
# Usage:
#   backup.sh [all|mariadb|wordpress|n8n|configs|maintenance]
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

backup_n8n() {
  log "dump n8n PostgreSQL -> restic (tag=n8n-postgres)"
  # pg_dump runs inside the container so we do not need a postgres client
  # on the host. PGPASSWORD + -U come from the container's own env, which
  # the compose file populates from /data/n8n/.env.
  # --clean --if-exists makes the dump idempotent on restore.
  docker exec "$N8N_POSTGRES_CONTAINER" \
    sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --clean --if-exists -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  | restic backup --stdin \
      --stdin-filename "n8n.sql" \
      --tag n8n-postgres \
      --host "$BACKUP_HOST"

  log "backup n8n files -> restic (tag=n8n-files)"
  restic backup \
    --tag n8n-files \
    --host "$BACKUP_HOST" \
    "${BACKUP_PATHS_N8N[@]}"
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

main() {
  local target="${1:-all}"
  case "$target" in
    mariadb)     backup_mariadb ;;
    wordpress)   backup_wordpress ;;
    configs)     backup_configs ;;
    n8n)         backup_n8n ;;
    all)
      backup_mariadb
      backup_wordpress
      backup_n8n
      backup_configs
      forget_old
      ;;
    maintenance) maintenance ;;
    *) echo "usage: $0 [all|mariadb|wordpress|n8n|configs|maintenance]" >&2; exit 2 ;;
  esac
  log "done ($target)"
}

main "$@"
