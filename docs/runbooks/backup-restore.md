# Runbook: Backup & Restore (t4a-t2)

> **Server:** t4a-t2 (AlmaLinux 9)
> **Tool:** [restic](https://restic.net/) over SFTP
> **Destination:** Hetzner Storage Box (SSH alias `t4a-storagebox`)
> **Scope:** MariaDB (logical dumps), WordPress files (`/mnt/vdc/www/t4a`), server configs
> **Schedule:** nightly backup at ~03:00, weekly prune + integrity check Sun ~04:00
> **Retention:** 7 daily, 4 weekly, 6 monthly (per `host,tags` group)

## What gets backed up

| Tag         | Source                                       | How                                         |
|-------------|----------------------------------------------|---------------------------------------------|
| `mariadb`   | all databases                                | `mariadb-dump --single-transaction` via stdin |
| `wordpress` | `/mnt/vdc/www/t4a`                           | filesystem (excludes WP caches + `*.log`)   |
| `configs`   | `/etc/nginx`, `/etc/letsencrypt`, `/etc/my.cnf.d`, `/etc/fstab`, systemd units, docker-compose dirs (including `.env` files) | filesystem |

### Are `.env` files safe to back up?

**Yes — include them.** Restic encrypts every chunk client-side with AES-256 + Poly1305 before anything leaves the server, using a key derived from your repo password. What arrives on the Storage Box is an opaque encrypted blob; without the repo password and a restic binary it is unreadable.

The blast radius of a compromise is therefore:

- **Repo password + SSH key to the Storage Box** → full access to everything in backups.
- **SSH key alone** → attacker can corrupt/delete backup data but cannot read it.
- **Repo password alone** → useless without the backup files.

Mitigations already baked into this setup:

1. `RESTIC_PASSWORD_FILE` is root-only (`chmod 600`, owned by `root`).
2. SSH identity is a dedicated key (`~/.ssh/hetzner_storagebox`), not reused elsewhere.
3. Repo password is also stored off-server in a password manager — losing the file locally does not lock you out.

Excluding `.env` files would mean a restore from a wiped server cannot bring the stack back up, so the tradeoff falls clearly on "include them".

## One-time setup

### 1. SSH access from the server to the Storage Box

Run on **t4a-t2** as root (backups run as root so the config must live in `/root`):

```bash
# SSH key for the Storage Box
ls -l /root/.ssh/hetzner_storagebox || {
  cp /home/<your-user>/.ssh/hetzner_storagebox /root/.ssh/
  chown root:root /root/.ssh/hetzner_storagebox
  chmod 600 /root/.ssh/hetzner_storagebox
}

# SSH config — must contain the t4a-storagebox host alias
cat >> /root/.ssh/config <<'EOF'
Host t4a-storagebox
    HostName u578499.your-storagebox.de
    User u578499
    Port 23
    IdentityFile ~/.ssh/hetzner_storagebox
    IdentitiesOnly yes
EOF
chmod 600 /root/.ssh/config

# Sanity check — this should list the Storage Box home dir
ssh t4a-storagebox ls
```

### 2. Generate + store the restic repo password

```bash
# 32 random bytes, base64-ish. Keep the output visible — save it to your password manager NOW.
openssl rand -base64 32 | tee /root/.restic-password
chmod 600 /root/.restic-password
chown root:root /root/.restic-password
```

**Save the same password in your password manager.** If `/root/.restic-password` is lost and you have not stored it elsewhere, every existing backup becomes permanently unreadable.

### 3. Create a dedicated MariaDB backup user

The backup script calls `mariadb-dump` with `/root/.my.cnf` credentials. Use a least-privilege user, not `root`.

```bash
mysql -u root -p <<'SQL'
CREATE USER IF NOT EXISTS 'backup'@'localhost' IDENTIFIED BY 'CHANGE_ME_STRONG_PASSWORD';
GRANT SELECT, SHOW VIEW, RELOAD, PROCESS, LOCK TABLES, EVENT, TRIGGER ON *.* TO 'backup'@'localhost';
FLUSH PRIVILEGES;
SQL
```

Create `/root/.my.cnf` (note the socket path matches the datadir documented in the MariaDB runbook):

```bash
cat > /root/.my.cnf <<'EOF'
[client]
user=backup
password=CHANGE_ME_STRONG_PASSWORD
socket=/mnt/vdc/mysql/mysql.sock
EOF
chmod 600 /root/.my.cnf
chown root:root /root/.my.cnf

# Smoke test
mariadb -e "SELECT CURRENT_USER();"
# Expected: backup@localhost
```

### 4. Initialize the restic repository

```bash
export RESTIC_REPOSITORY="sftp:t4a-storagebox:restic/t4a-t2"
export RESTIC_PASSWORD_FILE="/root/.restic-password"

restic init
# Expected: "created restic repository <id> at sftp:..."
```

If you see `repository master key and config already initialized` the repo already exists — skip to the next step.

### 5. Install the script, env file, and systemd units

The reference copies live in this repo under `scripts/`. From your workstation:

```bash
# From the t4a-ops repo root, copy to the server:
scp scripts/backup.sh               t4a-t2:/usr/local/bin/t4a-backup.sh
scp scripts/backup.env.example      t4a-t2:/etc/t4a-backup.env
scp scripts/systemd/t4a-backup*.{service,timer} t4a-t2:/etc/systemd/system/
```

On **t4a-t2**:

```bash
chmod 750 /usr/local/bin/t4a-backup.sh
chown root:root /usr/local/bin/t4a-backup.sh

chmod 600 /etc/t4a-backup.env
chown root:root /etc/t4a-backup.env

# Edit /etc/t4a-backup.env — in particular, uncomment and add your
# docker-compose directories in BACKUP_PATHS_CONFIGS so .env files ride along.
vi /etc/t4a-backup.env

systemctl daemon-reload
```

### 6. First backup (manual, one tag at a time so failures are obvious)

```bash
/usr/local/bin/t4a-backup.sh configs     # smallest, test paths first
/usr/local/bin/t4a-backup.sh mariadb
/usr/local/bin/t4a-backup.sh wordpress

# Confirm snapshots exist
restic -r "$RESTIC_REPOSITORY" -p /root/.restic-password snapshots
```

You should see three snapshots, one per tag, with host `t4a-t2`.

### 7. Enable the timers

```bash
systemctl enable --now t4a-backup.timer
systemctl enable --now t4a-backup-maintenance.timer

# Verify next-run times
systemctl list-timers 't4a-backup*'
```

## Daily operations

### Check latest run

```bash
systemctl status t4a-backup.service
journalctl -u t4a-backup.service -n 100 --no-pager
```

### List snapshots

```bash
source <(grep -E '^(RESTIC|BACKUP_HOST)=' /etc/t4a-backup.env | sed 's/^/export /')
export RESTIC_PASSWORD_FILE
restic snapshots --group-by 'host,tags'
```

### Repo size and stats

```bash
restic stats --mode raw-data
restic stats latest
```

### Trigger a backup outside the schedule

```bash
systemctl start t4a-backup.service      # runs the full "all" job
# or:
/usr/local/bin/t4a-backup.sh mariadb    # just one tag
```

## Restore procedures

All restores are read-only against the repo — they cannot corrupt existing backups. Always restore to a **scratch directory first** and verify before overwriting production data.

### Restore a single WordPress file or directory

```bash
# Find the snapshot with the file
restic find --tag wordpress "wp-config.php"

# Restore a specific path from the latest wordpress snapshot
mkdir -p /tmp/restore
restic restore latest --tag wordpress \
  --target /tmp/restore \
  --include /mnt/vdc/www/t4a/<site>/wp-config.php

# Diff, then move into place
diff /tmp/restore/mnt/vdc/www/t4a/<site>/wp-config.php /mnt/vdc/www/t4a/<site>/wp-config.php
```

### Restore the whole WordPress tree

```bash
mkdir -p /tmp/restore
restic restore latest --tag wordpress --target /tmp/restore
# Inspect /tmp/restore/mnt/vdc/www/t4a, then rsync into place if it looks good.
```

### Restore a MariaDB dump

```bash
mkdir -p /tmp/restore
restic restore latest --tag mariadb --target /tmp/restore
ls -lh /tmp/restore/all-databases.sql

# Dry-run sanity check (show first CREATE TABLE statements)
head -200 /tmp/restore/all-databases.sql

# Restore into a scratch DB first to validate, not straight into prod
mysql -u root -p -e "CREATE DATABASE restore_test;"
mysql -u root -p restore_test < /tmp/restore/all-databases.sql
# ... verify ...
mysql -u root -p -e "DROP DATABASE restore_test;"

# Only once verified, replay into production (this overwrites existing data)
mysql -u root -p < /tmp/restore/all-databases.sql
```

### Browse a snapshot interactively (FUSE mount)

Useful when you're hunting for the right version of a file across snapshots.

```bash
dnf install -y fuse fuse-libs    # if not already installed
mkdir -p /mnt/restic
restic mount /mnt/restic &
# Browse /mnt/restic/snapshots/<date>/... as a normal filesystem
fusermount -u /mnt/restic    # when done
```

### Full disaster recovery (bare server)

1. Provision a new AlmaLinux 9 instance, attach the `/dev/vdc` block volume.
2. Install restic, copy `/root/.ssh/hetzner_storagebox`, `/root/.ssh/config`, and the repo password into `/root/.restic-password`.
3. `restic restore latest --tag configs --target /` → brings back nginx, letsencrypt, my.cnf, systemd units, docker-compose dirs (including `.env`).
4. Install MariaDB per the [MariaDB Maintenance runbook](./mariadb-maintenance.md), then `restic restore latest --tag mariadb --target /tmp/restore && mysql < /tmp/restore/all-databases.sql`.
5. `restic restore latest --tag wordpress --target /`.
6. `systemctl daemon-reload && systemctl enable --now mariadb nginx docker t4a-backup.timer t4a-backup-maintenance.timer`.
7. Bring docker stacks up (`docker compose up -d` in each `/opt/docker/*` directory).

## Monitoring

### Is the timer firing?

```bash
systemctl list-timers 't4a-backup*'
# Look at NEXT/LAST columns — LAST should be within ~24h.
```

### Did last night's run succeed?

```bash
systemctl is-failed t4a-backup.service     # should print "active" or "inactive"
journalctl -u t4a-backup.service --since yesterday --no-pager
```

### Are snapshots fresh?

```bash
restic snapshots --group-by 'host,tags' --latest 1
# The "Time" column for each tag should be < 30 hours old.
```

### Optional: alert on silent failures

Silent failures (backup never runs) are more dangerous than loud ones. Two simple options:

- **systemd `OnFailure=`** — add an `OnFailure=status-email-root@%n.service` drop-in that emails on any non-zero exit. Catches crashes, not missed runs.
- **healthchecks.io** — add `curl -fsS https://hc-ping.com/<uuid>` as the last step of `backup.sh`. Their dashboard pages you when the ping *doesn't* arrive.

## Troubleshooting

### `Fatal: unable to open config file: ssh: ... connection refused`

SSH to the Storage Box is broken. Run `ssh t4a-storagebox ls` as root and fix the transport layer before investigating restic.

### `Fatal: wrong password or no key found`

`/root/.restic-password` does not match the repo master key. Restore it from your password manager — the repo cannot be re-keyed without the existing password.

### `mariadb-dump: Got error: 1045: Access denied`

The MariaDB backup user lost its grants (e.g. after a datadir reinit). Re-run step 3 of the one-time setup.

### Repo locked by a previous run

```bash
restic unlock             # removes stale non-exclusive locks
restic unlock --remove-all    # only if you are sure no restic process is running
```

### Repo is growing faster than expected

```bash
restic stats --mode raw-data
restic forget --group-by 'host,tags' --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --dry-run
# If forget --dry-run shows nothing, check whether retention in backup.sh matches what you actually want.
# If forget shows snapshots to drop but size still grows, maintenance prune has not run — trigger it:
systemctl start t4a-backup-maintenance.service
```

## Escalation

- Storage Box unreachable from t4a-t2 but reachable elsewhere: check Hetzner robot panel for Storage Box status and any SSH key changes on the server account.
- `restic check` reports pack errors: do **not** run `prune` until resolved. Open a ticket with Hetzner referencing the specific pack IDs from the check output.
- Lost both `/root/.restic-password` **and** the password-manager copy: backups are permanently unrecoverable. Re-init a new repo under a new path and start over — and add the password to your password manager this time.

---

*Created: April 2026 — T4A Ops*
