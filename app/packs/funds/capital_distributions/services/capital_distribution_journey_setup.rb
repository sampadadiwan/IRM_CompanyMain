# The capital distribution journeys: what JourneySetup seeds for distributions (the seeding itself,
# idempotency and the dry run live in JourneySetup).
#
#   Full  — "Capital Distribution — Full: Notify Investors" (10 tasks, including a CFO sign-off with no approvers yet)
#   Light — "Capital Distribution — Light: Record Only" (3 tasks)
#   Rules — imported distributions (manual_generation) → Light, priority 10; every other → Full, 100
#
# Order: payments are completed BEFORE investors are emailed — the app only emails a completed
# payment (the reverse of capital calls, which send before collecting). The notice tasks are not
# applicable when the fund has no Distribution Template (design Decision 7).
#
# The step lists below are what the Capital Distributions user guide documents task by task, so adding,
# renaming or removing one here means editing its journey section in
# docs/user_guides/capital_distributions_user_guide.md too.
# Worked examples H1, H2, H9 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
class CapitalDistributionJourneySetup < JourneySetup
  WORKFLOWABLE_TYPE = "CapitalDistribution".freeze
  KEY_PREFIX = "capital_distribution.".freeze
  LABEL = "capital distribution journeys".freeze
  RECORD = "distribution".freeze # what the setup button's messages call one record
  FULL_KEY = "capital_distribution_full".freeze
  LIGHT_KEY = "capital_distribution_light".freeze
  FULL_NAME = "Capital Distribution — Full: Notify Investors".freeze
  LIGHT_NAME = "Capital Distribution — Light: Record Only".freeze
  DESCRIPTION = "Tracks each capital distribution from payments to unit redemption. Seeded by CapHive; " \
                "admins can add approval steps or remove tasks.".freeze

  # [name, kind, check, skip, unlocks, description]
  FULL_STEPS = [
    ["Create payments", "system", "create_payments", nil, nil,
     "Every commitment has a payment (or the payment upload has finished)."],
    ["Generate notices", "system", "generate_notices", "notices_not_used", nil,
     "Every investor who is emailed has a generated distribution notice. Unverified KYC blocks a notice. " \
     "Not applicable when the fund has no Distribution Template."],
    ["Approve notices", "system", "approve_notices", "notices_not_used", nil,
     "Every generated distribution notice has been approved on the Documents screen."],
    ["Review custom notification", "acknowledge", "review_email", "review_not_needed", nil,
     "Someone has read the distribution email (custom notification) investors will receive and clicked Mark reviewed."],
    ["Check preview", "acknowledge", "check_preview", "review_not_needed", nil,
     "Someone has previewed the email (a payment's Preview Notification) and clicked Mark reviewed."],
    ["CFO sign-off", "human", nil, nil, nil,
     "The CFO signs off before the distribution is approved. Pick the approver(s) by editing this step."],
    ["Approve distribution", "system", "approve_distribution", "imported", nil,
     "The distribution is approved by an approver. Not applicable to imported distributions."],
    ["Mark payments completed", "system", "complete_payments", nil, nil,
     "Every payment is marked completed."],
    ["Email investors", "system", "email_investors", "no_email", nil,
     "Every investor who should be emailed has been sent the distribution email."],
    ["Redeem units", "system", "redeem_units", "no_unit_prices", nil,
     "Every completed payment with a face value for redemption has redeemed units. " \
     "Not applicable when the distribution has no unit prices."]
  ].freeze
  LIGHT_STEP_NAMES = ["Create payments", "Mark payments completed", "Redeem units"].freeze

  # Imported distributions get Light
  APPROVE_STEP_NAME = "Approve distribution".freeze
  LIGHT_CONDITIONS = [{ "attribute" => "manual_generation", "operator" => "eq", "value" => "true" }].freeze
end
