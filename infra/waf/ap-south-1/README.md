# WAF backup — ap-south-1 (Mumbai)

Exported from AWS WAFv2 (REGIONAL scope) on 2026-06-23 as a config backup. Not auto-synced — re-run the export if the live ACL changes.

- `CapHive.web_acl.json` — full Web ACL (`aws wafv2 get-web-acl`), associated with the `appLb-production-82f2e1d` ALB.
- `ipset.Blacklist.json` — the IPSet referenced by the ACL's `Blacklist` rule.

To restore or clone into another region: recreate the IPSet first (`create_ip_set` with the addresses above), then `create_web_acl` using `rules` from the Web ACL file, rewriting the `Blacklist` rule's `ip_set_reference_statement.arn` to point at the new IPSet's ARN. `id`, `arn`, and `capacity` are read-only and excluded automatically by `create_web_acl`.
