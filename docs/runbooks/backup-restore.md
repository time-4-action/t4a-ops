# Runbook: Backup & Restore (t4a-t2)

> **Server:** t4a-t2 (AlmaLinux 9)
> **Tool:** [restic](https://restic.net/) over SFTP
> **Destination:** Hetzner Storage Box (SSH alias `t4a-storagebox`)
> **Scope:** MariaDB (logical dumps), WordPress files (`/mnt/vdc/www/t4a`), n8n (Postgres dump + `/data/n8n` files), MongoDB (logical dump), server configs
> **Schedule:** nightly backup at ~03:00, weekly prune + integrity check Sun ~04:00
> **Retention:** 7 daily, 4 weekly, 6 monthly (per `host,tags` group)
>
> **Coverage map** (what IS and what ISN'T backed up): see [backup-coverage.md](./backup-coverage.md).

## What gets backed up

| Tag            | Source                                       | How                                         |
|----------------|----------------------------------------------|---------------------------------------------|
| `mariadb`      | all databases                                | `mariadb-dump --single-transaction` via stdin |
| `wordpress`    | `/mnt/vdc/www/t4a`                           | filesystem (excludes WP caches + `*.log`)   |
| `n8n-postgres` | n8n PostgreSQL database                      | `docker exec n8n_postgres pg_dump --clean --if-exists` via stdin |
| `n8n-files`    | `/data/n8n/n8n_data`, `/data/n8n/local-files` | filesystem (workflow defs, credentials, uploads) |
| `mongodb`      | all MongoDB databases (`/data/mongo`)        | `mongodump --uri=$MONGO_URI --archive` via stdin        |
| `configs`      | `/etc/nginx`, `/etc/letsencrypt`, `/etc/my.cnf.d`, `/etc/mongod.conf`, `/etc/fstab`, systemd units, all docker-compose YAMLs + their `.env`/`.env.local` files under `/data/**/` | filesystem (explicit file list in `backup.env.example`) |

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

### 4. Create a dedicated MongoDB backup user

MongoDB auth is enabled, so `mongodump` needs credentials. Use the built-in `backup` role (read-only across all databases).

```bash
mongosh -u <admin_user> -p --authenticationDatabase admin
```

Inside the shell:

```js
use admin
db.createUser({
  user: "backup",
  pwd: "STRONG_PASSWORD",
  roles: ["backup"]
})
exit
```

Add to `/etc/t4a-backup.env`:

```bash
echo 'MONGO_URI="mongodb://backup:STRONG_PASSWORD@localhost:27017/?authSource=admin"' \
  >> /etc/t4a-backup.env

# Smoke test
mongodump --uri="mongodb://backup:STRONG_PASSWORD@localhost:27017/?authSource=admin" \
  --archive --dryRun 2>&1 | head -5
```

### 4a. Initialize the restic repository

```bash
export RESTIC_REPOSITORY="sftp:t4a-storagebox:restic/t4a-t2"
export RESTIC_PASSWORD_FILE="/root/.restic-password"

restic init
# Expected: "created restic repository <id> at sftp:..."
```

If you see `repository master key and config already initialized` the repo already exists — skip to the next step.

### 5. Install the script, env file, and systemd units

The t4a-ops repo is cloned on **t4a-t2** (typically at `/root/t4a-ops`). Run the
following as root from the repo root — `install` sets mode + ownership in one
call, so no separate `chmod`/`chown` needed and the commands are idempotent.

```bash
cd /root/t4a-ops        # or wherever the repo is cloned

# Script + systemd units — safe to re-run on every repo pull.
install -m 0750 -o root -g root  scripts/backup.sh                              /usr/local/bin/t4a-backup.sh
install -m 0644 -o root -g root  scripts/systemd/t4a-backup.service             /etc/systemd/system/
install -m 0644 -o root -g root  scripts/systemd/t4a-backup.timer               /etc/systemd/system/
install -m 0644 -o root -g root  scripts/systemd/t4a-backup-maintenance.service /etc/systemd/system/
install -m 0644 -o root -g root  scripts/systemd/t4a-backup-maintenance.timer   /etc/systemd/system/

# Env file — ONLY on first install, so a re-deploy never clobbers local edits.
# If backup.env.example grows new keys later, diff and merge by hand.
[[ -f /etc/t4a-backup.env ]] || install -m 0600 -o root -g root scripts/backup.env.example /etc/t4a-backup.env

systemctl daemon-reload
```

Then edit `/etc/t4a-backup.env` — check every path in `BACKUP_PATHS_CONFIGS`
exists on this host and comment out any that don't (e.g. certbot is left
commented in the template until you confirm its exact layout). Also set
`N8N_POSTGRES_CONTAINER` if the container name differs from `n8n_postgres`.

```bash
vi /etc/t4a-backup.env
```

For a full map of what each tag captures — and what is **not** backed up —
see [backup-coverage.md](./backup-coverage.md).

### 6. First backup (manual, one tag at a time so failures are obvious)

```bash
/usr/local/bin/t4a-backup.sh configs     # smallest, test paths first
/usr/local/bin/t4a-backup.sh mariadb
/usr/local/bin/t4a-backup.sh wordpress
/usr/local/bin/t4a-backup.sh n8n         # requires the n8n_postgres container to be up
/usr/local/bin/t4a-backup.sh mongodb     # requires mongod to be up and MONGO_URI set

# Confirm snapshots exist
restic -r "$RESTIC_REPOSITORY" -p /root/.restic-password snapshots
```

You should see snapshots for each tag (`configs`, `mariadb`, `wordpress`,
`n8n-postgres`, `n8n-files`, `mongodb`), all with host `t4a-t2`.

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

### Restore n8n (PostgreSQL + files)

n8n needs BOTH the `n8n-postgres` dump AND the `n8n-files` tree — the database
holds workflows/executions, but `n8n_data` holds the encryption key and config
that make the dumped credentials decryptable.

```bash
# 1. Stop n8n (keep postgres up — we need it for psql).
cd /data/n8n && docker compose stop n8n

# 2. Restore files (workflow definitions, N8N_ENCRYPTION_KEY, local uploads).
mkdir -p /tmp/restore
restic restore latest --tag n8n-files --target /tmp/restore
# Inspect /tmp/restore/data/n8n, then rsync into place:
rsync -a --delete /tmp/restore/data/n8n/n8n_data/    /data/n8n/n8n_data/
rsync -a --delete /tmp/restore/data/n8n/local-files/ /data/n8n/local-files/

# 3. Restore the Postgres dump into the running container.
restic restore latest --tag n8n-postgres --target /tmp/restore
docker exec -i n8n_postgres \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < /tmp/restore/n8n.sql

# 4. Start n8n and verify.
docker compose up -d n8n
docker logs -f n8n
```

If workflow credentials show as "unable to decrypt", the `N8N_ENCRYPTION_KEY`
in `/data/n8n/.env` no longer matches the one used when the dump was taken.
Restore `/data/n8n/n8n_data/config` from the same snapshot as the SQL dump.

### Restore a MongoDB dump

```bash
mkdir -p /tmp/restore
restic restore latest --tag mongodb --target /tmp/restore
ls -lh /tmp/restore/mongodb.archive

# Stop traffic to MongoDB-dependent services first (if any are running)

# Restore all databases from the archive.
# --drop: drop existing collections before restoring (safe for full recovery).
# --nsInclude='*.*': restore all namespaces (default; explicit for clarity).
mongorestore \
  --uri="mongodb://admin_user:ADMIN_PASS@localhost:27017/?authSource=admin" \
  --archive=/tmp/restore/mongodb.archive \
  --drop

# Verify
mongosh -u admin_user -p --authenticationDatabase admin \
  --eval "db.adminCommand({ listDatabases: 1 })"
```

To restore a single database only (e.g. `mydb`):

```bash
mongorestore \
  --uri="mongodb://admin_user:ADMIN_PASS@localhost:27017/?authSource=admin" \
  --archive=/tmp/restore/mongodb.archive \
  --nsInclude='mydb.*' \
  --drop
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
7. Restore n8n filesystem state: `restic restore latest --tag n8n-files --target /`.
8. Bring docker stacks up (`docker compose up -d` in each stack directory: `/data/patrik/`, `/data/n8n/`, `/data/stack/apps/time-4-action/{admin,chat,export,mcp,sync}/`, `/data/certbot/`). Postgres will come up with an empty DB.
9. Replay the n8n Postgres dump into the fresh container — see the "Restore n8n" section above.

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

### `config error: N8N_POSTGRES_CONTAINER is not set` / `Fatal: nothing to backup`

`/etc/t4a-backup.env` is missing variables that were added to `backup.env.example` after initial deploy. The install step (step 5) never overwrites an existing env file, so new keys must be merged by hand.

```bash
diff <(grep -E '^[A-Z_]+=|^[A-Z_]+\(' /root/t4a-ops/scripts/backup.env.example) \
     <(grep -E '^[A-Z_]+=|^[A-Z_]+\(' /etc/t4a-backup.env)
# Copy any missing keys from the example into /etc/t4a-backup.env, then:
sudo /usr/local/bin/t4a-backup.sh all
```

### `Fatal: unable to open config file: ssh: ... connection refused`

SSH to the Storage Box is broken. Run `ssh t4a-storagebox ls` as root and fix the transport layer before investigating restic.

### `Fatal: wrong password or no key found`

`/root/.restic-password` does not match the repo master key. Restore it from your password manager — the repo cannot be re-keyed without the existing password.

### `config error: MONGO_URI is not set`

`MONGO_URI` was added to `backup.env.example` after your initial deploy. Since the install step never overwrites an existing env file, merge it by hand:

```bash
diff <(grep -E '^[A-Z_]+=|^[A-Z_]+\(' /root/t4a-ops/scripts/backup.env.example) \
     <(grep -E '^[A-Z_]+=|^[A-Z_]+\(' /etc/t4a-backup.env)
# Add missing MONGO_URI line to /etc/t4a-backup.env, then re-run.
```

### `mongodump: Failed: (Unauthorized)`

The MongoDB backup user doesn't have the `backup` role or the `authSource` in `MONGO_URI` is wrong. Verify:

```bash
mongosh -u backup -p --authenticationDatabase admin --eval "db.runCommand({connectionStatus:1})"
```

If it fails, re-create the user (step 4 of one-time setup). Ensure `MONGO_URI` ends with `?authSource=admin`.

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
