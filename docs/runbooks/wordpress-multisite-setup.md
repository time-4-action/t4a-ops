# Runbook: WordPress Multi-Site Provisioning (nginx + PHP-FPM + MariaDB)

> **Server:** t4a-t2 (AlmaLinux 9)  
> **Stack:** nginx · PHP 8.5 (Remi) · MariaDB · WordPress  
> **Mount:** `/var/www/t4a/` on `/dev/vdc` (ext4 block volume)

## Symptoms

- New WordPress site needs to be provisioned on the T4A instance
- Existing WordPress site is returning 403/502/blank page after setup
- PHP-FPM or MariaDB not running after server reboot
- Block volume `/var/www/t4a/` not mounted

## Diagnosis

1. Check block volume is mounted:
   ```bash
   df -h /var/www/t4a
   blkid /dev/vdc
   ```

2. Check PHP-FPM status:
   ```bash
   php -v
   systemctl status php-fpm
   ```

3. Check MariaDB status:
   ```bash
   systemctl status mariadb
   ```

4. Check nginx config is valid:
   ```bash
   nginx -t
   ```

5. Check SELinux context on web root:
   ```bash
   ls -Z /var/www/t4a/
   getenforce
   ```

---

## Resolution

### A. First-Time Server Setup (one-time)

These steps configure the base stack. Skip to **Section B** if the server is already provisioned.

#### A1. Mount the block volume

```bash
# Verify device and filesystem
blkid /dev/vdc
# Expected: UUID="346c682e-7f9e-4d2e-80ad-28d8c90f5004" TYPE="ext4"

mkdir -p /var/www/t4a
mount /dev/vdc /var/www/t4a

# Persist across reboots
echo "UUID=346c682e-7f9e-4d2e-80ad-28d8c90f5004  /var/www/t4a  ext4  defaults  0  2" >> /etc/fstab

# Validate fstab (catches errors before reboot)
mount -a
df -h /var/www/t4a
```

> **Why UUID over /dev/vdc?** OpenStack block devices can reorder between reboots. UUID is stable.

#### A2. Install PHP 8.5 via Remi

```bash
# Install Remi repository
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm

# Reset default PHP module and enable 8.5
dnf module reset php -y
dnf module enable php:remi-8.5 -y

# Install PHP + WordPress-required extensions
dnf install -y php php-fpm php-mysqlnd php-xml php-mbstring php-json \
  php-curl php-zip php-gd php-intl php-opcache php-bcmath

systemctl enable --now php-fpm
php -v
```

**Required extensions:** mysqlnd (DB), xml (RSS/sitemaps), mbstring (multibyte), json (REST/Gutenberg), curl (HTTP), zip (plugin installs), gd (images), intl (i18n), opcache (performance), bcmath (WooCommerce).

#### A3. Configure PHP-FPM for nginx

Edit `/etc/php-fpm.d/www.conf`:

```ini
user = nginx
group = nginx
listen = /run/php-fpm/www.sock
listen.owner = nginx
listen.group = nginx
listen.mode = 0660
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
```

```bash
systemctl reload php-fpm
```

> For sites with different traffic profiles, consider separate FPM pools per site (`/etc/php-fpm.d/site1.conf`).

#### A4. Install and secure MariaDB

```bash
dnf install -y mariadb-server mariadb
systemctl enable --now mariadb
mysql_secure_installation
```

#### A5. Open firewall ports

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

#### A6. Set SELinux contexts

```bash
# Allow nginx to serve from /var/www/t4a
semanage fcontext -a -t httpd_sys_content_t "/var/www/t4a(/.*)?"
restorecon -Rv /var/www/t4a

# Allow writes to upload dirs (run per site after WordPress install)
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/t4a/.*/wp-content/uploads(/.*)?"
restorecon -Rv /var/www/t4a
```

---

### B. Provision a New WordPress Site

Repeat these steps for each new site.

#### B1. Create database

```sql
CREATE DATABASE wp_<sitename> CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wp_<sitename>_user'@'localhost' IDENTIFIED BY '<strong_password>';
GRANT ALL PRIVILEGES ON wp_<sitename>.* TO 'wp_<sitename>_user'@'localhost';
FLUSH PRIVILEGES;
```

> **Convention:** DB = `wp_{sitename}`, user = `wp_{sitename}_user`. Store credentials outside web root.

#### B2. Install WordPress

```bash
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/t4a/<site.domain.com>/

cd /var/www/t4a/<site.domain.com>
cp wp-config-sample.php wp-config.php
```

Edit `wp-config.php`:

```php
define( 'DB_NAME',     'wp_<sitename>' );
define( 'DB_USER',     'wp_<sitename>_user' );
define( 'DB_PASSWORD', '<strong_password>' );
define( 'DB_HOST',     'localhost' );
define( 'DB_CHARSET',  'utf8mb4' );

// Generate fresh salts from: https://api.wordpress.org/secret-key/1.1/salt/
```

#### B3. Set permissions

```bash
chown -R nginx:nginx /var/www/t4a/<site.domain.com>
find /var/www/t4a/<site.domain.com> -type d -exec chmod 755 {} \;
find /var/www/t4a/<site.domain.com> -type f -exec chmod 644 {} \;
chmod 600 /var/www/t4a/<site.domain.com>/wp-config.php
```

#### B4. Create nginx vhost

Create `/etc/nginx/conf.d/<site.domain.com>.conf`:

```nginx
server {
    listen 80;
    server_name <site.domain.com> www.<site.domain.com>;

    root /var/www/t4a/<site.domain.com>;
    index index.php index.html;

    # WordPress permalink support
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # PHP-FPM handler
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    # Deny access to sensitive files
    location ~ /\.ht {
        deny all;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { log_not_found off; access_log off; allow all; }

    # Static file caching
    location ~* \.(css|gif|ico|jpeg|jpg|js|png|svg|webp|woff2)$ {
        expires max;
        log_not_found off;
    }

    access_log /var/log/nginx/<site.domain.com>.access.log;
    error_log  /var/log/nginx/<site.domain.com>.error.log;
}
```

#### B5. Enable and verify

```bash
nginx -t
systemctl reload nginx
```

#### B6. Add SSL (once DNS is pointed)

```bash
certbot --nginx -d <site.domain.com> -d www.<site.domain.com>
```

---

## Directory Structure

```
/var/www/t4a/
├── site1.domain.com/        # WordPress root for site 1
│   ├── wp-admin/
│   ├── wp-content/
│   ├── wp-includes/
│   └── wp-config.php
├── site2.domain.com/        # WordPress root for site 2
│   └── ...
└── ...
```

Each site is a **separate WordPress install** (not WordPress Multisite). This isolates sites, allows per-site vhosts, and simplifies per-site backups.

## Monitoring

- Check PHP-FPM is running:
  ```bash
  systemctl status php-fpm
  ```
- Check MariaDB is running:
  ```bash
  systemctl status mariadb
  ```
- Check block volume is mounted:
  ```bash
  df -h /var/www/t4a
  ```
- Check nginx error logs per site:
  ```bash
  tail -50 /var/log/nginx/<site.domain.com>.error.log
  ```
- Check PHP-FPM error log:
  ```bash
  journalctl -u php-fpm --since "1 hour ago"
  ```

## Rollback

- **Bad fstab entry:** Boot into rescue mode, fix `/etc/fstab`, reboot. Always validate with `mount -a` before rebooting.
- **PHP upgrade broke sites:** Downgrade via `dnf module reset php && dnf module enable php:remi-8.4 && dnf update php*`, then restart php-fpm.
- **Remove a WordPress site:** Drop the DB (`DROP DATABASE wp_<sitename>`), remove the directory (`rm -rf /var/www/t4a/<site.domain.com>`), delete the nginx vhost, reload nginx.

## Escalation

- PHP-FPM won't start: check `journalctl -u php-fpm` and `/etc/php-fpm.d/www.conf` syntax
- SELinux denials: `ausearch -m avc -ts recent` and apply appropriate `semanage fcontext` rules
- MariaDB connection refused: check `systemctl status mariadb` and MySQL user grants
- nginx 502 Bad Gateway: verify PHP-FPM socket exists at `/run/php-fpm/www.sock` and socket permissions match nginx user

---

*Created: April 2026 — T4A Ops*
