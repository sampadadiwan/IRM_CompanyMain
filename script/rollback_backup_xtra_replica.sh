#!/usr/bin/env bash
#
# rollback_backup_xtra_replica.sh
#
# Reverts everything migrate_backup_xtra_replica.sh created, returning IN
# production S3 to its pre-migration state. The bucket-migration approach was
# abandoned in favour of pointing the app at the EXISTING replica bucket via
# AWS_S3_BUCKET_REPLICA_XTRA (see .env.production.in and
# DbBackupFreshnessJob), so the half-created conventional bucket, its
# replication rule and its IAM policy are now just clutter to remove.
#
# What it removes, in dependency-safe order (each step skips cleanly if the
# migration never reached it):
#   1. The "conventional" replication rule on the primary backup bucket.
#      MUST happen first — the rule is live and writes new incrementals into
#      the new bucket every 30 min; deleting the bucket while the rule points
#      at it would cause replication failures on the primary.
#   2. The extra inline IAM policy on the replication role.
#   3. Every object VERSION and delete marker in the new bucket (it was
#      created with versioning, so a plain delete would fail), then the
#      bucket itself.
#
# What it NEVER touches: the primary bucket, the old replica bucket
# (docs.caphive.com.production-backup-xtra-ap-south2), the original
# replication rule to it, or the role's pre-existing policies. It refuses to
# run at all if the original rule is not still enabled.
#
# Usage (IN production credentials, account 825199636520):
#   ./script/rollback_backup_xtra_replica.sh --dry-run   # print actions only
#   ./script/rollback_backup_xtra_replica.sh             # asks for confirmation
#
# Requirements: aws CLI v2, jq.

set -euo pipefail

# ---------------------------------------------------------------------------
# Same fixed configuration as the migration script — hardcoded so this can
# only ever act on the exact resources the migration created.
# ---------------------------------------------------------------------------
EXPECTED_ACCOUNT="825199636520"
PRIMARY_BUCKET="docs.caphive.com.production-backup-xtra"
PRIMARY_REGION="ap-south-1"
OLD_REPLICA_BUCKET="docs.caphive.com.production-backup-xtra-ap-south2"
NEW_REPLICA_BUCKET="docs.caphive.com.production.ap-south-2-backup-xtra"   # the ONLY bucket this script deletes
REPLICA_REGION="ap-south-2"
REPLICATION_ROLE="S3AccessForReplication"
EXTRA_POLICY_NAME="replicate-to-conventional-backup-xtra"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Echo + execute (or just echo in dry-run mode). Used for every mutating call.
run() {
  echo "+ $*"
  if ! $DRY_RUN; then "$@"; fi
}

# ---------------------------------------------------------------------------
# Preflight — verify account and that the ORIGINAL replication path is intact
# before we remove anything, so rollback can never leave prod without a
# working replica.
# ---------------------------------------------------------------------------
command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 1; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]]; then
  echo "ERROR: connected to AWS account $ACCOUNT, expected IN production ($EXPECTED_ACCOUNT). Aborting."
  exit 1
fi
echo "✓ AWS account confirmed: $ACCOUNT"

CONFIG=$(aws s3api get-bucket-replication --bucket "$PRIMARY_BUCKET" --query ReplicationConfiguration)
if ! echo "$CONFIG" | jq -e --arg b "arn:aws:s3:::$OLD_REPLICA_BUCKET" \
     '.Rules[] | select(.Destination.Bucket == $b and .Status == "Enabled")' >/dev/null; then
  echo "ERROR: the ORIGINAL replication rule to $OLD_REPLICA_BUCKET is not enabled."
  echo "       Rolling back now would leave production with no working replica. Aborting."
  exit 1
fi
echo "✓ Original replication rule to old replica is intact"

# Deleting a bucket full of DB backups deserves an explicit human yes.
if ! $DRY_RUN; then
  echo
  echo "This will PERMANENTLY DELETE s3://$NEW_REPLICA_BUCKET (all versions) and"
  echo "the DbBackupFreshnessJob NoSuchBucket alert will resume until re-migrated."
  read -r -p "Type the bucket name to confirm: " CONFIRM
  if [[ "$CONFIRM" != "$NEW_REPLICA_BUCKET" ]]; then
    echo "Confirmation did not match. Aborting."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 1. Remove the migration's replication rule (leave every other rule as-is).
#    Done FIRST so replication stops writing into the bucket we're deleting.
# ---------------------------------------------------------------------------
if echo "$CONFIG" | jq -e --arg b "arn:aws:s3:::$NEW_REPLICA_BUCKET" \
     '.Rules[] | select(.Destination.Bucket == $b)' >/dev/null; then
  # Filter out only the rule targeting the new bucket; everything else is
  # passed back verbatim.
  REVERTED=$(echo "$CONFIG" | jq --arg b "arn:aws:s3:::$NEW_REPLICA_BUCKET" \
    '.Rules |= map(select(.Destination.Bucket != $b))')
  echo "Replication configuration after removing the migration rule:"
  echo "$REVERTED" | jq .
  run aws s3api put-bucket-replication \
    --bucket "$PRIMARY_BUCKET" \
    --region "$PRIMARY_REGION" \
    --replication-configuration "$REVERTED"
  echo "✓ Migration replication rule removed (original rule untouched)"
else
  echo "✓ No replication rule to the new bucket found — migration never reached step 4, skipping"
fi

# ---------------------------------------------------------------------------
# 2. Remove the extra inline policy the migration added to the role. The
#    role's pre-existing policies are not listed or touched.
# ---------------------------------------------------------------------------
if aws iam get-role-policy --role-name "$REPLICATION_ROLE" --policy-name "$EXTRA_POLICY_NAME" >/dev/null 2>&1; then
  run aws iam delete-role-policy \
    --role-name "$REPLICATION_ROLE" \
    --policy-name "$EXTRA_POLICY_NAME"
  echo "✓ Extra inline policy removed from $REPLICATION_ROLE"
else
  echo "✓ Extra inline policy not present — skipping"
fi

# ---------------------------------------------------------------------------
# 3. Empty and delete the new bucket. It is versioned, so every object
#    version AND delete marker must go before delete-bucket succeeds.
# ---------------------------------------------------------------------------
if ! aws s3api head-bucket --bucket "$NEW_REPLICA_BUCKET" 2>/dev/null; then
  echo "✓ New bucket does not exist — nothing to delete"
else
  if $DRY_RUN; then
    COUNT=$(aws s3api list-object-versions --bucket "$NEW_REPLICA_BUCKET" --region "$REPLICA_REGION" \
      --output json | jq '[.Versions[]?, .DeleteMarkers[]?] | length')
    echo "+ (would delete all $COUNT+ object versions/markers, then the bucket)"
  else
    # delete-objects accepts at most 1000 keys per call, which matches the
    # list page size — loop until the bucket is completely empty.
    while :; do
      PAGE=$(aws s3api list-object-versions \
        --bucket "$NEW_REPLICA_BUCKET" --region "$REPLICA_REGION" \
        --max-keys 1000 --output json)
      BATCH=$(echo "$PAGE" | jq '{Objects: ([.Versions[]?, .DeleteMarkers[]?] | map({Key, VersionId})), Quiet: true}')
      COUNT=$(echo "$BATCH" | jq '.Objects | length')
      [[ "$COUNT" -eq 0 ]] && break
      echo "Deleting batch of $COUNT object versions/markers..."
      aws s3api delete-objects \
        --bucket "$NEW_REPLICA_BUCKET" --region "$REPLICA_REGION" \
        --delete "$BATCH" >/dev/null
    done
    echo "✓ Bucket emptied"
  fi

  run aws s3api delete-bucket --bucket "$NEW_REPLICA_BUCKET" --region "$REPLICA_REGION"
  echo "✓ Bucket $NEW_REPLICA_BUCKET deleted"
fi

# ---------------------------------------------------------------------------
# Final verification — show that the original replication path survived.
# ---------------------------------------------------------------------------
if $DRY_RUN; then
  echo "DRY RUN complete — no changes were made."
  exit 0
fi

echo
echo "=== Verification ==="
echo "Replication rules now on $PRIMARY_BUCKET:"
aws s3api get-bucket-replication --bucket "$PRIMARY_BUCKET" \
  --query "ReplicationConfiguration.Rules[].{ID:ID,Status:Status,Dest:Destination.Bucket}" --output table

cat <<'EOF'

Rollback complete. Reminder:
  - The freshness alert stays fixed only once the app is deployed/restarted
    with AWS_S3_BUCKET_REPLICA_XTRA set (see .env.production.in) so
    DbBackupFreshnessJob checks the real replica bucket
    (docs.caphive.com.production-backup-xtra-ap-south2).
EOF
