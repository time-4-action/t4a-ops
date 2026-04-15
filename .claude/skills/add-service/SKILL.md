---
name: add-service
description: Add a new service to the t4a-ops inventory. Prompts for all required fields and updates both services.md and repositories.md tables. Use when registering a new application or microservice.
disable-model-invocation: true
argument-hint: [service-name]
allowed-tools: Read Edit Grep
---

Add a new service called **$ARGUMENTS** to the inventory.

## Gather information

Ask the user for the following (skip any they already provided):

| Field | Example | Required |
|-------|---------|----------|
| Service name | `t4a-web` | Yes (from args) |
| Repository | `t4a-org/t4a-web` | Yes |
| Server(s) / IP(s) | `10.0.0.1, 10.0.0.2` | Yes |
| Port | `3000` | Yes |
| Status | Active / Inactive / Staging | Yes |
| Primary language | TypeScript | For repo table |
| CI/CD | GitHub Actions / None | For repo table |
| Notes | any context | Optional |

## Update files

1. Read `inventory/services.md` and add a new row to the table, keeping alphabetical order by service name.
2. Read `inventory/repositories.md` and add a row if the repository isn't already listed.
3. If the server IP(s) are not yet in `inventory/servers.md`, tell the user to also run `/add-server`.

## Validation

- No duplicate service names in `services.md`
- No duplicate repository entries in `repositories.md`
- Port numbers must be numeric
