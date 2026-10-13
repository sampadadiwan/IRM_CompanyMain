# The dealing-date journey (US-6): one template; pre-funded-only and pay-after-only steps are skipped by
# the dealing date's payment timing, and subscription / redemption steps when it has none of them.
# Seeded per entity by EvergreenEnable; its catch-all rule launches it on every new dealing date.
# Worked examples H16, H17, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingDateJourneySetup < JourneySetup
  WORKFLOWABLE_TYPE = "DealingDate".freeze
  KEY_PREFIX = "dealing_date.".freeze
  LABEL = "evergreen dealing date journey".freeze
  RECORD = "dealing date".freeze
  FULL_KEY = "dealing_date".freeze
  FULL_NAME = "Evergreen Dealing Date".freeze
  FULL_LABEL = "Evergreen Dealing Date".freeze
  SIGN_OFF_NAME = nil
  DESCRIPTION = "Runs each evergreen dealing date from collecting money to closing. Seeded by CapHive.".freeze

  # [name, kind, check, skip, unlocks, description]
  FULL_STEPS = [
    ["Collect subscription money", "system", "collect_money", "not_pre_funded", nil,
     "Every subscription is paid, or the cut-off has passed (funds paid before dealing)."],
    ["Approve NAV", "system", "approve_nav", nil, nil,
     "Every class with orders has an approved NAV on or before the dealing date."],
    ["Review and confirm dealing", "system", "confirm", nil, nil,
     "The dealing date's pricing and gate have been reviewed and confirmed."],
    ["Send payment instructions", "system", "instructions_sent", "not_pay_after", nil,
     "Every subscriber has been sent payment instructions with the exact units (funds paid after dealing)."],
    ["Collect subscription money after dealing", "system", "collect_money_after", "not_pay_after", nil,
     "Every subscription payment is recorded and verified (funds paid after dealing)."],
    ["Allot units", "system", "allotted", "no_subscriptions", nil,
     "Every subscription has its units allotted (contract notes are emailed now when the fund has no template)."],
    ["Pay redemptions", "system", "redemptions_paid", "no_redemptions", nil,
     "Every filled redemption is marked paid."],
    ["Cancel units", "system", "units_cancelled", "no_redemptions", nil,
     "Every paid redemption has its units cancelled (advices are emailed now when the fund has no template)."],
    # Optional: only when the fund has a Contract Note / Redemption Advice template (§ Dealing-date documents)
    ["Generate documents", "system", "documents_generated", "no_document_templates", nil,
     "Contract notes and redemption advices are generated from the fund's templates (Generate documents)."],
    ["Approve and send documents", "system", "documents_sent", "no_document_templates", nil,
     "Every generated document is approved and emailed to its investor with the PDF attached (Approve & send)."],
    ["Close dealing date", "system", "closed", nil, nil,
     "Someone clicked Close dealing date once everything settled."]
  ].freeze
end
