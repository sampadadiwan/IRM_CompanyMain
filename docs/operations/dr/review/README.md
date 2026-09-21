# DR & Landing-Zone Review — Index

> Operator docs: `docs/operations/dr/dr_guide.md` (what to do in an incident) ·
> `docs/operations/dr/db_backup_system.md` (how the backup system works, end to end) ·
> `docs/operations/dr/dr_drills.md` (drill log). This folder is the design/decision trail.

A point-by-point hardening of the IRM infrastructure (July 2026), driven by the goal:
**a complete, unattended DR — AMI creation, AWS setup, database recovery — and one-command new landing zones.**
Each doc records the issue, the code trace, the fix, blast radius, and verification steps.

## The punchline

Before: DR required a human at a keyboard end-to-end (STDIN pauses, manual SSH restore, manual commit, manual crontab install, manual DNS/SES), backups relied on an uninstalled crontab comment, and **five separate latent bugs would each have broken a real recovery** (un-deployable DR stack config ×2, restore that destroys the only local copy, backup chain corrupted by verifier instances, nil IPs written into credentials).

After: `rake "aws:setup_infra[production, AppServer, DB-Redis-ES, ap-south-2, in, production.in, <branch>]"` runs the whole recovery unattended; backups are baked into the AMI, self-arming, replicated cross-region, retention-managed, encrypted, and freshness-monitored hourly; `rake aws:dr_drill` proves the chain quarterly with a measured RTO; DNS cutover and SES are one-command but deliberately human-triggered.

## Point index

| # | Doc | Status |
|---|---|---|
| 1 | [Pulumi ap-south-2 config errors](point_01_pulumi_ap_south_2_config_errors.md) | ✅ |
| 2 | [Restore deleted datadir without backup](point_02_restore_deletes_datadir_without_backup.md) | ✅ |
| 3 | [Committed secrets](point_03_committed_secrets.md) | ⚠️ partial (SSH key kept by request; rotations pending) |
| 4 | [Stale runbook + stack-naming mismatch](point_04_runbook_stale_and_stack_naming_mismatch.md) | ✅ |
| 5 | [DB backups baked into the AMI, self-arming](point_05_codify_db_backup_crontab.md) | ✅ |
| 6 | [S3 replication + CORS codified](point_06_s3_replication_codified.md) | ✅ |
| 7 | [Backup-freshness alerting](point_07_backup_freshness_alert.md) | ✅ |
| 8 | [90-day retention lifecycle](point_08_backup_retention_lifecycle.md) | ✅ |
| 9 | [Bucket encryption](point_09_bucket_encryption.md) | ✅ |
| 10+11 | [Non-interactive DR + migration replay](point_10_11_noninteractive_dr.md) | ✅ |
| 12+13 | [State backend migration + DR drill](point_12_13_state_backend_and_drill.md) | ✅ code; state migration awaits operator run |
| 14 | [Region-agnostic Pulumi](point_14_region_agnostic_pulumi.md) | ✅ |
| 15 | [Packer build network](point_15_packer_build_network.md) | ✅ |
| 16 | [SES + DNS cutover (manual-only tools)](point_16_ses_dns_manual_automation.md) | ✅ |
| 17–19 | [Stack-output handoff, scoped IAM, pins + CI](point_17_18_19_handoff_iam_ci.md) | ✅ |

## Operator checklist (AWS-side activation — run when ready)

The code is complete; these one-time commands activate it (order matters):

1. **Pulumi state migration** (needs your Pulumi login): `cd ../IRM-Infra && PULUMI_CONFIG_PASSPHRASE=... ./migrate_state_to_s3.sh irm-pulumi-state ap-south-1` — then store the passphrase in Rails credentials.
2. **Verify stack re-attachment**: `pulumi stack ls`, then `pulumi preview` per stack — expect zero diffs from the renames/plain-keys/dynamic-AZ changes, and the planned IAM changes from Point 18.
3. **Seed SSM backup params** per env × region: `rake "xtrabackup:seed_ssm_params[production.in, ap-south-1]"` (and ap-south-2, us-east-1, staging pair).
4. **`pulumi up` per stack** — attaches DB instance profiles (Point 5) and applies the scoped app role (Point 18).
5. **Provision S3** per env: `rake "aws:provision_s3_buckets[production.in]"` — replication/CORS/retention/encryption. ⚠️ First lifecycle sweep deletes backups older than 90 days.
6. **Credentials**: add `MYSQL_ROOT_PASSWORD` + `PULUMI_CONFIG_PASSPHRASE`; rotate live DB root passwords (old one is in git history); decide on the deploy SSH key (Point 3).
7. **Next weekly AMI bake** picks up the baked backup tooling automatically.
8. **First DR drill**: `TEARDOWN=true rake "aws:dr_drill[in]"` — the measured-RTO proof that all of the above works.
