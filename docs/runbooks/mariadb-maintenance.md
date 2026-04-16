# Runbook: MariaDB Maintenance (t4a-t2)

> **Server:** t4a-t2 (AlmaLinux 9)  
> **Version:** MariaDB 10.5.29 (dnf)  
> **Datadir:** `/mnt/vdc/mysql/`  
> **Socket:** `/mnt/vdc/mysql/mysql.sock`

## Symptoms

- WordPress sites returning "Error establishing a database connection"
- MariaDB service won't start after reboot
- `mysql` CLI returns `Can't connect to local MySQL server through socket`
- SELinux denials blocking database access

## Diagnosis

1. Check MariaDB status:
   ```bash
   systemctl status mariadb
   ```

2. Verify datadir is correct:
   ```bash
   mysql -u root -p -e "SELECT @@datadir;"
   # Expected: /mnt/vdc/mysql/
   ```

3. Check block volume is mounted:
   ```bash
   df -h /mnt/vdc
   ```

4. Check socket exists:
   ```bash
   ls -la /mnt/vdc/mysql/mysql.sock
   ```

5. Check SELinux denials:
   ```bash
   ausearch -m avc -ts recent | tail -20
   ```

6. Check error log:
   ```bash
   tail -30 /var/log/mariadb/mariadb.log
   ```

## Resolution

### MariaDB won't start — socket path error

The error `Can't start server: Bind on unix socket: No such file or directory` means the socket path doesn't match an existing directory.

Verify both config files point to the same socket:

```bash
grep socket /etc/my.cnf.d/mariadb-server.cnf
grep socket /etc/my.cnf.d/client.cnf
```

Both must show `/mnt/vdc/mysql/mysql.sock`.

### MariaDB won't start — SELinux denial

```bash
sudo dnf install -y policycoreutils-python-utils

# Label custom datadir for MariaDB
sudo semanage fcontext -a -t mysqld_db_t "/mnt/vdc/mysql(/.*)?"
sudo restorecon -Rv /mnt/vdc/mysql
```

### MariaDB won't start — block volume not mounted

```bash
# Check fstab entry exists
grep vdc /etc/fstab
# Expected: /dev/vdc  /mnt/vdc  ext4  defaults  0  2

# Mount manually
mount /mnt/vdc

# Verify
df -h /mnt/vdc
ls -la /mnt/vdc/mysql/
```

### Reinitialize database (data loss — last resort)

```bash
sudo mysql_install_db --user=mysql --datadir=/mnt/vdc/mysql
sudo systemctl start mariadb
sudo mysql_secure_installation
```

### Create a new WordPress database

```sql
CREATE DATABASE wp_<sitename> CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wp_<sitename>_user'@'localhost' IDENTIFIED BY '<strong_password>';
GRANT ALL PRIVILEGES ON wp_<sitename>.* TO 'wp_<sitename>_user'@'localhost';
FLUSH PRIVILEGES;
```

> Use `utf8mb4` with `unicode_ci` — required for emoji and special character support in WordPress.

### Service management

```bash
sudo systemctl start mariadb
sudo systemctl stop mariadb
sudo systemctl restart mariadb
sudo systemctl enable mariadb    # start on boot
```

## Configuration Reference

### /etc/my.cnf.d/mariadb-server.cnf

```ini
[mysqld]
datadir=/mnt/vdc/mysql
socket=/mnt/vdc/mysql/mysql.sock
log-error=/var/log/mariadb/mariadb.log
pid-file=/run/mariadb/mariadb.pid
```

### /etc/my.cnf.d/client.cnf

```ini
[client]
socket=/mnt/vdc/mysql/mysql.sock

[client-mariadb]
socket=/mnt/vdc/mysql/mysql.sock
```

### Directory ownership

```bash
sudo chown -R mysql:mysql /mnt/vdc/mysql
sudo chmod 750 /mnt/vdc/mysql
```

## Monitoring

- Test connectivity:
  ```bash
  mysql -h localhost -u root -p -e "SELECT 1;"
  nc -zv localhost 3306
  ```
- Check error log: `tail -30 /var/log/mariadb/mariadb.log`
- Check service status: `systemctl status mariadb`
- Check disk usage on block volume: `df -h /mnt/vdc`

## Escalation

- SELinux keeps blocking after `restorecon`: check `ausearch -m avc -ts recent` for the exact denial and create a custom policy module if needed
- Data corruption: check `/var/log/mariadb/mariadb.log` for InnoDB recovery messages
- Block volume not appearing: check OpenStack dashboard for volume attachment status

---

*Created: April 2026 — T4A Ops*
