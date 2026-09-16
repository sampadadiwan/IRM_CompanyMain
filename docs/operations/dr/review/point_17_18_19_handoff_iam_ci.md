# DR Review — Points 17+18+19: Stack-output handoff, scoped app IAM, pins + CI

**Status:** ✅ Applied (all syntax checks pass)
**Repos affected:** `IRM` and `IRM-Infra`

---

## Point 17: `pulumi stack output` replaces the output.json handoff

`setup_infra` and `aws:dns_cutover` now read outputs via `pulumi stack output --json --stack <name>` (new `pulumi_stack_output` helper in `aws_utils.rb`). The old `../IRM-Infra/output.json` read had a serious flaw beyond the nil-wrapper bug fixed in Point 16: the file is written by whichever stack ran `pulumi up` **last on that machine** — orchestrating stack A after touching stack B silently handed you the *wrong region's IPs*. Stack-scoped output queries cannot be stale or cross-wired. (`outputs.py` still writes the local file for debugging; it's gitignored and no longer load-bearing.)

## Point 18: App-server IAM scoped down (and de-collided)

`RailsAppRole` was an **account-global fixed name** (two stacks in one account collide on create) carrying **AmazonS3FullAccess + AmazonEC2FullAccess** — every web server could delete any bucket or terminate any instance in the account.

Now: `RailsAppRole-<region>-<stack>` with one inline policy granting only what's actually used:

| Statement | Grants | Used by |
|---|---|---|
| S3ObjectAccess | object CRUD + listing (no bucket admin) | app storage (attachments) |
| EC2OperationalAccess | describe, AMI bake ops, snapshot, tags, instance lifecycle | weekly `aws:create_and_copy_ami` cron; `DbRestoreService` |
| DbCheckInstanceIam | create/get/pass role+profile, **scoped to `DbCheckInstance*` names** | `DbRestoreService` runtime IAM |

Gone: bucket deletion/policy, VPC/SG mutation, and every other FullAccess power nothing uses.

**Rollout note:** `pulumi preview` will show the old role replaced and instances updated to the new profile — apply stack by stack, and re-run the 4-hourly `DbRestoreJob` once afterwards to confirm the scoped IAM statements suffice (its create-role path is the most exotic consumer).

## Point 19: Version pins + CI

- `requirements.txt`: `pulumi>=3.203.0,<4` / `pulumi-aws>=7.9.0,<8` (the versions the stacks were last deployed with — an unpinned major bump could change resource diffs mid-DR).
- **`IRM-Infra/.github/workflows/ci.yml`** (new): Python syntax, shellcheck on ops scripts, and a **stack-config completeness gate** — every `Pulumi.*.yaml` must carry exactly the required key set and a `*.`-prefixed domain. This is the check that would have caught Point 1's both bugs the day they were introduced.
- **`IRM/.github/workflows/infra-checks.yml`** (new, paths-filtered to infra files only — doesn't touch the app's own pipeline): `ruby -c` on all rake tasks + `deploy.rb`, `bash -n` + advisory shellcheck on the backup script, `packer validate -syntax-only` on the three templates.

Neither workflow needs AWS credentials; both run in seconds.

## Verification

1. All local equivalents of the CI checks pass (they were run as part of applying).
2. First push of the `dr_improvement` branches will exercise both workflows end-to-end.
3. Point 18's real gate: `pulumi preview` per stack + one `DbRestoreJob` cycle post-apply.
