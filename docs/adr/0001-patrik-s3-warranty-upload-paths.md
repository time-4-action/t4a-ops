# ADR-0001: Patrik — S3 Warranty Upload Paths and Presigned URL Flow

- **Status:** Accepted
- **Date:** 2026-04-18
- **Author:** grega-rotar

## Context

The Patrik warranty claim form requires users to upload up to four file attachments (invoice, serial number photo, full product photo, close-up photo). Files must be stored durably and served publicly. A legacy set of warranty files was migrated from WordPress/ARForms and needs to coexist in the same bucket under a stable path.

## Decision

Use a single Hetzner Object Storage bucket (`patrik-assets`, region `fsn1`) with two top-level path prefixes:

### New uploads

```
uploads/warranty/<submissionId>/<slot>.<ext>
```

- `submissionId` — `crypto.randomUUID()` generated once per form submission in `WarrantyForm.tsx`; groups all four files for one claim
- `slot` — one of `invoice`, `serial`, `full`, `closeup`
- `ext` — original file extension from the uploaded filename

Public base URL: `https://patrik-assets.fsn1.your-objectstorage.com`

Example:
```
https://patrik-assets.fsn1.your-objectstorage.com/uploads/warranty/f47ac10b-58cc-4372-a567-0e02b2c3d479/invoice.jpg
```

### Legacy archive

```
archive/warranty/<filename>
```

- Flat structure; preserves original ARForms filenames
- Migrated from `https://patrik-international.com/warranty/wp-content/uploads/arforms/userfiles/<filename>` via Cyberduck (one-off, not scripted)
- MongoDB is the source of truth mapping archive files to warranty claims

### Upload flow (new submissions)

1. `WarrantyForm.tsx` generates one `submissionId` on form submit
2. For each slot, calls `POST /api/upload-url` with `{ submissionId, slot, filename, contentType }`
3. API returns a presigned PUT URL (5-min TTL) and the final public URL
4. Browser uploads directly to Hetzner S3 via the presigned URL — Next.js server never proxies file bytes
5. Public URLs are passed with the form payload for backend processing

## Consequences

**Easier:**
- Slot names are fixed and predictable; no filename collisions within a submission
- UUID-based submission grouping makes it trivial to list or delete all files for a claim
- Browser-direct upload removes load from the Next.js server

**Harder:**
- Legacy files have no embedded metadata; MongoDB must be authoritative for archive lookups
- Presigned URLs expire after 5 minutes — slow connections or large files could cause upload failures

## Rollback Plan

No data migration required to roll back the upload flow — presigned URL generation is stateless. To revert to server-proxied uploads, remove the `POST /api/upload-url` endpoint and handle multipart form data directly in the Next.js API route.
