---
name: add-server
description: Add a new server to the t4a-ops server inventory. Prompts for all required fields and updates servers.md. Use when provisioning or documenting a new server.
disable-model-invocation: true
argument-hint: [hostname]
allowed-tools: Read Edit Grep
---

Add a new server called **$ARGUMENTS** to the inventory.

## Gather information

Ask the user for the following (skip any they already provided):

| Field | Example | Required |
|-------|---------|----------|
| Hostname | `prod-web-01` | Yes (from args) |
| IP address | `10.0.0.1` | Yes |
| Role | App Server / DB / Proxy / Worker | Yes |
| OS | Ubuntu 24.04 | Yes |
| Provider | Hetzner / AWS / DigitalOcean | Yes |
| Services running | `t4a-web, t4a-api` | Yes |
| Notes | specs, region, etc. | Optional |

## Update files

1. Read `inventory/servers.md` and add a new row, keeping rows sorted by hostname.
2. Cross-check: for each service listed, verify it exists in `inventory/services.md`. If not, tell the user to also run `/add-service`.

## Validation

- No duplicate hostnames or IPs in `servers.md`
- IP must look like a valid IPv4 or IPv6 address
