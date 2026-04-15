# Runbook: SSL Certificate Renewal (t4a.etiam.si)

## Symptoms

- Browser shows "certificate expired" or "not secure" for any `*.t4a.etiam.si` domain
- nginx returns TLS handshake errors
- Certbot renewal logs show failures in `/data/certbot/logs/renew.log`

## Diagnosis

1. Check cert expiry date:
   ```bash
   openssl x509 -enddate -noout -in /data/certbot/config/live/t4a.etiam.si/cert.pem
   ```

2. Check certbot renewal status:
   ```bash
   certbot certificates --config-dir /data/certbot/config --work-dir /data/certbot/work --logs-dir /data/certbot/logs
   ```

3. Test a dry-run renewal:
   ```bash
   certbot renew --dry-run \
     --config-dir /data/certbot/config \
     --work-dir /data/certbot/work \
     --logs-dir /data/certbot/logs
   ```

4. Check Cloudflare credentials are valid:
   ```bash
   cat /data/certbot/credentials/cloudflare.ini
   ```

## Resolution

1. Force renewal:
   ```bash
   certbot renew --force-renewal \
     --config-dir /data/certbot/config \
     --work-dir /data/certbot/work \
     --logs-dir /data/certbot/logs
   ```

2. Reload nginx to pick up new cert:
   ```bash
   systemctl reload nginx
   ```

3. If Cloudflare API token expired, generate a new one in Cloudflare dashboard and update `/data/certbot/credentials/cloudflare.ini`.

## Monitoring

- Verify cert is renewed:
  ```bash
  echo | openssl s_client -connect t4a.etiam.si:443 -servername t4a.etiam.si 2>/dev/null | openssl x509 -noout -dates
  ```
- Check renewal log: `/data/certbot/logs/renew.log`

## Escalation

- Cloudflare DNS issues: check Cloudflare dashboard
- Certbot bugs: check `/data/certbot/logs/letsencrypt.log`
