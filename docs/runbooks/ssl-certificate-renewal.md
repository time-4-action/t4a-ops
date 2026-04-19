# Runbook: SSL / TLS Certificate Management

## Strategy: Cloudflare Origin Certificates

All domains are proxied through Cloudflare (orange cloud). TLS is terminated at Cloudflare for browsers. Between Cloudflare → origin server we use **Cloudflare Origin Certificates** — free, 15-year validity, zero renewal automation needed.

Cloudflare SSL/TLS mode must be set to **Full (strict)**.

> Origin Certificates are only trusted by Cloudflare. If you ever disable the Cloudflare proxy (grey cloud) for a domain, browsers will reject the cert. That is expected — don't do it in production.

---

## Certificate storage on server

```
/etc/cloudflare-origin/
  <project-name>/
    origin.crt   # chmod 644
    origin.key   # chmod 600
```

Permissions:
```bash
chmod 755 /etc/cloudflare-origin/
chmod 755 /etc/cloudflare-origin/<project-name>/
chmod 644 /etc/cloudflare-origin/<project-name>/origin.crt
chmod 600 /etc/cloudflare-origin/<project-name>/origin.key
```

Backed up via `BACKUP_PATHS_CONFIGS` in `/etc/t4a-backup.env` (see `scripts/backup.env.example`).

---

## Issuing a new Origin Certificate

1. Cloudflare dashboard → select domain → **SSL/TLS → Origin Server → Create Certificate**
2. Choose **RSA**, add `yourdomain.com` and `*.yourdomain.com`, set validity to **15 years**
3. Copy the certificate and private key to the server:
   ```bash
   mkdir -p /etc/cloudflare-origin/<project-name>
   vi /etc/cloudflare-origin/<project-name>/origin.crt   # paste cert
   vi /etc/cloudflare-origin/<project-name>/origin.key   # paste key
   chmod 644 /etc/cloudflare-origin/<project-name>/origin.crt
   chmod 600 /etc/cloudflare-origin/<project-name>/origin.key
   ```
4. Point nginx at the new cert (see nginx config below)
5. Reload nginx: `systemctl reload nginx`

## nginx config snippet

```nginx
ssl_certificate     /etc/cloudflare-origin/<project-name>/origin.crt;
ssl_certificate_key /etc/cloudflare-origin/<project-name>/origin.key;
```

---

## Deployed certificates

| Project dir | Domains covered | Issued |
|---|---|---|
| `the-chase-project` | the-chase-project domains | 2026-04-19 |

---

## Diagnosis

Check cert expiry (should be ~15 years out):
```bash
openssl x509 -enddate -noout -in /etc/cloudflare-origin/<project-name>/origin.crt
```

Verify nginx is serving it:
```bash
echo | openssl s_client -connect yourdomain.com:443 -servername yourdomain.com 2>/dev/null | openssl x509 -noout -dates
```

Test nginx config before reload:
```bash
nginx -t
```

---

## Escalation

- Wrong SSL mode in Cloudflare → browser SSL errors even if cert is valid — check **SSL/TLS → Overview**, must be **Full (strict)**
- Cert not found → check path in nginx conf matches `/etc/cloudflare-origin/<project>/origin.crt`
- Cloudflare dashboard → SSL/TLS → Origin Server to view/revoke issued certs
