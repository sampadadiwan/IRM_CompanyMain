# Support Console — the provisioning rake tasks (lib/tasks/support_console/*.rake), the parts that can
# be checked without AWS. Worked examples: openspec/changes/support-console/design.md#worked-examples
@support_console
Feature: Support Console provisioning

  # X32 — Error case: production.in and production.us share an AWS account, so a REGION override that names the other region is refused
  Scenario: REGION override refused on production
    When the provisioning region is worked out for "production.in" with REGION "us-east-1"
    Then it is refused with "share an AWS account"
    When the provisioning region is worked out for "production.in" with REGION "ap-south-1"
    Then the region is "ap-south-1"
    When the provisioning region is worked out for "production.us" with REGION ""
    Then the region is "us-east-1"
    When the provisioning region is worked out for "staging.in" with REGION "us-east-1"
    Then the region is "us-east-1"
