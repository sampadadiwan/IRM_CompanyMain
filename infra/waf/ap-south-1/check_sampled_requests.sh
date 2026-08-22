#!/usr/bin/env bash
# Diagnose why a request to /grafana/alert got a 403 at the ALB/WAF edge.
#
# GetSampledRequests only covers the last 3 hours, so run this soon after
# the 403 you're chasing — the 2026-08-22 06:31:18 UTC hit that triggered
# this script's existence is likely already outside that window.
#
# Requires: AWS CLI configured with credentials for account 825199636520
# (ap-south-1, the account that owns the CapHive Web ACL — see
# infra/waf/ap-south-1/README.md). jq for formatting.
#
# Usage:
#   ./check_sampled_requests.sh [hours_back]   # default 3, max 3 (API limit)

set -euo pipefail

WEB_ACL_ARN="arn:aws:wafv2:ap-south-1:825199636520:regional/webacl/CapHive/9c60a75f-55d8-494d-ac45-50f952132fcc"
REGION="ap-south-1"
HOURS_BACK="${1:-3}"

if ! command -v jq >/dev/null; then
  echo "jq is required" >&2
  exit 1
fi

END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_TIME=$(date -u -d "-${HOURS_BACK} hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-"${HOURS_BACK}"H +%Y-%m-%dT%H:%M:%SZ)  # -d is GNU date, -v is BSD date (macOS)

echo "Querying WAF samples from ${START_TIME} to ${END_TIME}..." >&2

# RuleMetricName = the Web ACL's own metric name ("CapHive") returns samples
# for every request the ACL evaluated, tagged with whichever rule terminated
# it — not just one rule's matches. That's what we need to identify the
# culprit among the 6 rules in the ACL.
aws wafv2 get-sampled-requests \
  --region "$REGION" \
  --web-acl-arn "$WEB_ACL_ARN" \
  --rule-metric-name "CapHive" \
  --scope REGIONAL \
  --time-window "StartTime=${START_TIME},EndTime=${END_TIME}" \
  --max-items 500 \
  > /tmp/waf_samples.json

echo "--- Requests to /grafana/alert ---"
jq -r '
  .SampledRequests[]
  | select(.Request.URI == "/grafana/alert")
  | [.Timestamp, .Action, (.RuleNameWithinRuleGroup // "n/a"), .Request.ClientIP]
  | @tsv
' /tmp/waf_samples.json | column -t -s $'\t' -N TIMESTAMP,ACTION,RULE,CLIENT_IP

echo
echo "--- All BLOCK actions in the window (in case URI matching above found nothing) ---"
jq -r '
  .SampledRequests[]
  | select(.Action == "BLOCK")
  | [.Timestamp, .Request.URI, (.RuleNameWithinRuleGroup // "n/a"), .Request.ClientIP]
  | @tsv
' /tmp/waf_samples.json | column -t -s $'\t' -N TIMESTAMP,URI,RULE,CLIENT_IP

echo
echo "Full response saved to /tmp/waf_samples.json"
