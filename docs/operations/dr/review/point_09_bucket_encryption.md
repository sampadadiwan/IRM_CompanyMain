# DR Review — Point 9: Default encryption at rest on all buckets

**Status:** ✅ Applied (`ruby -c` passes)
**Repo affected:** `IRM`
**File:** `lib/tasks/aws.rake` (`aws:provision_s3_buckets`)
**Severity:** Medium — the DB backup buckets hold full plaintext dumps of the production database; nothing codified guaranteed they were encrypted at rest. The backup script deliberately has no client-side encryption (keys on the DB box would defeat the Point 5 secret-free design), so bucket-level SSE is the enforcement point.

---

## 1. What was added

A fourth `ensure_*` phase in `aws:provision_s3_buckets`, same idempotency contract as replication/CORS/lifecycle:

| Existing state | Behaviour |
|---|---|
| Any encryption config (SSE-S3 or hand-configured SSE-KMS) | Left untouched, reported |
| No encryption at all (pre-Jan-2023 buckets) | Default **SSE-S3 (AES256)** applied |

Applied to all four buckets — app assets and DB backups, source and replica.

## 2. Design decisions

- **SSE-S3 over SSE-KMS, deliberately:** zero key management, no KMS grants needed for the replication role (KMS + cross-region replication needs extra key policy on both sides), and the DB instance role stays as tightly scoped as Point 5 left it. If a compliance requirement later demands customer-managed keys, the never-clobber contract means you can hand-configure SSE-KMS and re-runs of the task won't touch it.
- **Server-side, not client-side:** encrypting in the backup script would put key material on the DB server and complicate every restore path; SSE at the bucket covers the at-rest requirement with no operational surface.
- **New objects only:** default encryption applies at write time. Pre-existing unencrypted objects stay as-is — and age out within 90 days via the Point 8 lifecycle anyway.

## 3. Verification

1. Re-run `rake "aws:provision_s3_buckets[production.in]"` — buckets report either "already configured" (post-2023 buckets have SSE-S3 by default) or "applied".
2. `aws s3api get-bucket-encryption --bucket <bucket>-backup-xtra` shows AES256.
3. After the next backup tick: `aws s3api head-object` on a fresh chunk shows `ServerSideEncryption: AES256`.
