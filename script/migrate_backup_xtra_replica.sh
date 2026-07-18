#!/usr/bin/env bash
#
# migrate_backup_xtra_replica.sh
#
# One-off migration for IN production: bring the xtrabackup REPLICA bucket in
# line with the naming convention the app expects.
#
#   Code convention (db_backup_freshness_job.rb / aws.rake provision task):
#       #{AWS_S3_BUCKET_REPLICA}-backup-xtra
#       => docs.caphive.com.production.ap-south-2-backup-xtra   (MISSING)
#
#   What was created manually on 2025-07-23 instead:
#       docs.caphive.com.production-backup-xtra-ap-south2        (EXISTS, receiving replication)
#
# What this script does (ALL steps are additive — it never deletes or modifies
# existing buckets, objects, rules or policies):
#   1. Preflight: confirm we are in the IN production account and every
#      existing bucket is where we expect it.
#   2. Create the conventional bucket in ap-south-2 (versioning + public
#      access block), only if missing.
#   3. Grant the existing replication role write access to the NEW bucket via
#      an ADDITIONAL inline policy (the existing policy is left untouched).
#   4. ADD a second replication rule on the primary backup bucket targeting
#      the new bucket. The existing rule to the old bucket stays enabled, so
#      both replicas receive all future backups (S3 multi-destination
#      replication). Nothing breaks if this script is wrong — the old path
#      keeps working.
#   5. Backfill the new bucket with the newest FULL backup and every backup
#      taken after it, copied from the OLD replica (same region => fast, no
#      cross-region transfer cost). Older history is deliberately not copied —
#      it stays in the old bucket, which we are not deleting.
#   6. Verify: print what the DbBackupFreshnessJob will see in the new bucket.
#
# Decommissioning the old bucket/rule is intentionally NOT done here. Do that
# manually only after DbBackupFreshnessJob has been green for a few days.
#
# Usage (run with IN production credentials, account 825199636520):
#   ./script/migrate_backup_xtra_replica.sh --dry-run   # print actions only
#   ./script/migrate_backup_xtra_replica.sh             # do it
#
# Requirements: aws CLI v2, jq.

set -euo pipefail

# ---------------------------------------------------------------------------
# Fixed configuration for IN production (deliberately hardcoded so this cannot
# accidentally run against staging/US with the wrong bucket names).
# ---------------------------------------------------------------------------
EXPECTED_ACCOUNT="825199636520"                                        # IN production AWS account
PRIMARY_BUCKET="docs.caphive.com.production-backup-xtra"               # source of replication (ap-south-1)
PRIMARY_REGION="ap-south-1"
OLD_REPLICA_BUCKET="docs.caphive.com.production-backup-xtra-ap-south2" # manually-created, off-convention
NEW_REPLICA_BUCKET="docs.caphive.com.production.ap-south-2-backup-xtra" # conventional name the app checks
REPLICA_REGION="ap-south-2"
REPLICATION_ROLE="S3AccessForReplication"                              # role already used by the existing rule
# Additional inline policy we attach to the role (additive; existing policies untouched)
EXTRA_POLICY_NAME="replicate-to-conventional-backup-xtra"
NEW_RULE_ID="Replicate to conventional ap-south-2 backup-xtra bucket"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Echo + execute (or just echo in dry-run mode). Used for every mutating call.
run() {
  echo "+ $*"
  if ! $DRY_RUN; then "$@"; fi
}

# ---------------------------------------------------------------------------
# 1. Preflight checks — fail fast before touching anything.
# ---------------------------------------------------------------------------
command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 1; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]]; then
  echo "ERROR: connected to AWS account $ACCOUNT, expected IN production ($EXPECTED_ACCOUNT). Aborting."
  exit 1
fi
echo "✓ AWS account confirmed: $ACCOUNT"

# Both pre-existing buckets must be present — otherwise our mental model of
# the environment is wrong and we should not proceed.
aws s3api head-bucket --bucket "$PRIMARY_BUCKET"     || { echo "ERROR: primary bucket $PRIMARY_BUCKET not found"; exit 1; }
aws s3api head-bucket --bucket "$OLD_REPLICA_BUCKET" || { echo "ERROR: old replica bucket $OLD_REPLICA_BUCKET not found"; exit 1; }
echo "✓ Primary and old replica buckets exist"

# The existing replication rule to the old bucket must still be in place —
# we are adding alongside it, not repairing a broken setup.
EXISTING_CONFIG=$(aws s3api get-bucket-replication --bucket "$PRIMARY_BUCKET" --query ReplicationConfiguration)
if ! echo "$EXISTING_CONFIG" | jq -e --arg b "arn:aws:s3:::$OLD_REPLICA_BUCKET" \
     '.Rules[] | select(.Destination.Bucket == $b and .Status == "Enabled")' >/dev/null; then
  echo "ERROR: expected an Enabled replication rule to $OLD_REPLICA_BUCKET on $PRIMARY_BUCKET — found none. Aborting."
  exit 1
fi
echo "✓ Existing replication rule to old replica is enabled (will be left untouched)"

# ---------------------------------------------------------------------------
# 2. Create the conventional replica bucket (idempotent).
# ---------------------------------------------------------------------------
if aws s3api head-bucket --bucket "$NEW_REPLICA_BUCKET" 2>/dev/null; then
  echo "✓ New bucket $NEW_REPLICA_BUCKET already exists — skipping creation"
else
  # ap-south-2 is not us-east-1, so a LocationConstraint is required.
  run aws s3api create-bucket \
    --bucket "$NEW_REPLICA_BUCKET" \
    --region "$REPLICA_REGION" \
    --create-bucket-configuration "LocationConstraint=$REPLICA_REGION"
fi

# Versioning is mandatory on a replication destination. Enabling it repeatedly
# is a no-op, so no existence check needed.
run aws s3api put-bucket-versioning \
  --bucket "$NEW_REPLICA_BUCKET" \
  --region "$REPLICA_REGION" \
  --versioning-configuration Status=Enabled

# Backups must never be public; block all public access at the bucket level.
run aws s3api put-public-access-block \
  --bucket "$NEW_REPLICA_BUCKET" \
  --region "$REPLICA_REGION" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "✓ New bucket ready (versioned, public access blocked)"

# ---------------------------------------------------------------------------
# 3. Let the replication role write to the new bucket — as a NEW inline
#    policy, so the role's existing policies are never modified.
# ---------------------------------------------------------------------------
POLICY_DOC=$(jq -n --arg arn "arn:aws:s3:::$NEW_REPLICA_BUCKET" '{
  Version: "2012-10-17",
  Statement: [{
    Sid: "ReplicateIntoConventionalXtraReplica",
    Effect: "Allow",
    Action: [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
      "s3:ObjectOwnerOverrideToBucketOwner"
    ],
    Resource: ($arn + "/*")
  }]
}')
run aws iam put-role-policy \
  --role-name "$REPLICATION_ROLE" \
  --policy-name "$EXTRA_POLICY_NAME" \
  --policy-document "$POLICY_DOC"
echo "✓ Replication role can write to the new bucket"

# ---------------------------------------------------------------------------
# 4. Add a second replication rule (multi-destination replication).
#    The existing rule keeps replicating to the old bucket; the new rule sends
#    the same objects to the conventional bucket. Idempotent: skipped if a
#    rule for the new destination already exists.
# ---------------------------------------------------------------------------
if echo "$EXISTING_CONFIG" | jq -e --arg b "arn:aws:s3:::$NEW_REPLICA_BUCKET" \
     '.Rules[] | select(.Destination.Bucket == $b)' >/dev/null; then
  echo "✓ Replication rule to new bucket already exists — skipping"
else
  # New rule gets a priority strictly above every existing rule's priority
  # (priorities must be unique when multiple rules match the same objects).
  NEXT_PRIORITY=$(echo "$EXISTING_CONFIG" | jq '[.Rules[].Priority] | max + 1')
  # Append our rule to the existing config verbatim — everything already there
  # is preserved byte-for-byte. Multi-destination rules require the V2 schema
  # (Filter + Priority + DeleteMarkerReplication), which the existing rule
  # already uses. DeleteMarkerReplication stays Disabled to match the existing
  # rule: deletes/ransomware on the primary must not propagate to replicas.
  NEW_CONFIG=$(echo "$EXISTING_CONFIG" | jq \
    --arg id "$NEW_RULE_ID" \
    --arg b "arn:aws:s3:::$NEW_REPLICA_BUCKET" \
    --argjson prio "$NEXT_PRIORITY" \
    '.Rules += [{
      ID: $id,
      Priority: $prio,
      Filter: {},
      Status: "Enabled",
      Destination: { Bucket: $b },
      DeleteMarkerReplication: { Status: "Disabled" }
    }]')
  echo "New replication configuration to apply:"
  echo "$NEW_CONFIG" | jq .
  run aws s3api put-bucket-replication \
    --bucket "$PRIMARY_BUCKET" \
    --region "$PRIMARY_REGION" \
    --replication-configuration "$NEW_CONFIG"
  echo "✓ Second replication rule added (old rule untouched)"
fi

# ---------------------------------------------------------------------------
# 5. Backfill: copy the newest FULL backup and everything after it from the
#    OLD replica (same region — fast and free of cross-region charges).
#    Without this, the freshness job would alert "no FULL backup" until the
#    next nightly full (23:00) replicates. Replication only covers NEW
#    objects, never existing ones.
# ---------------------------------------------------------------------------
# Backups live under top-level prefixes named "<%F_%H%M%S>-full/" or "-incr/"
# (see db_backup_xtra.sh). Timestamps sort lexicographically, so plain sort
# gives chronological order.
PREFIXES=$(aws s3api list-objects-v2 \
  --bucket "$OLD_REPLICA_BUCKET" --region "$REPLICA_REGION" --delimiter "/" \
  --query "CommonPrefixes[].Prefix" --output text | tr '\t' '\n' | sort)

LATEST_FULL=$(echo "$PREFIXES" | grep -- "-full/$" | tail -1 || true)
if [[ -z "$LATEST_FULL" ]]; then
  echo "ERROR: no FULL backup prefix found in $OLD_REPLICA_BUCKET — nothing sane to backfill. Aborting before sync."
  exit 1
fi
echo "Newest full backup in old replica: $LATEST_FULL"

# Copy the latest full and every prefix (incrementals + any newer fulls)
# from that point on. `aws s3 sync` only copies missing/changed objects, so
# re-running is cheap and never clobbers replicated data with older bytes.
echo "$PREFIXES" | awk -v start="$LATEST_FULL" '$0 >= start' | while read -r prefix; do
  run aws s3 sync \
    "s3://$OLD_REPLICA_BUCKET/$prefix" \
    "s3://$NEW_REPLICA_BUCKET/$prefix" \
    --region "$REPLICA_REGION"
done
echo "✓ Backfill complete (latest full + newer backups)"

# ---------------------------------------------------------------------------
# 6. Verify: show the new bucket exactly the way DbBackupFreshnessJob sees it.
# ---------------------------------------------------------------------------
if $DRY_RUN; then
  echo "DRY RUN complete — no changes were made."
  exit 0
fi

echo
echo "=== Verification ==="
echo "Replication rules on $PRIMARY_BUCKET:"
aws s3api get-bucket-replication --bucket "$PRIMARY_BUCKET" \
  --query "ReplicationConfiguration.Rules[].{ID:ID,Status:Status,Dest:Destination.Bucket}" --output table

echo "Newest backup prefixes now in $NEW_REPLICA_BUCKET:"
aws s3api list-objects-v2 \
  --bucket "$NEW_REPLICA_BUCKET" --region "$REPLICA_REGION" --delimiter "/" \
  --query "CommonPrefixes[].Prefix" --output text | tr '\t' '\n' | sort | tail -5

cat <<'EOF'

Done. Next steps:
  1. DbBackupFreshnessJob (hourly) should go green on its next run — or check
     immediately with:  rake s3:check_backup_freshness
  2. Leave BOTH replication rules running for a few days.
  3. Once the freshness job has been green across a nightly full (23:00),
     optionally decommission the old rule + bucket MANUALLY. This script
     never deletes anything.
EOF
