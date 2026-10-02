# The capital call journeys: what JourneySetup seeds for calls (the seeding itself, idempotency
# and the dry run live in JourneySetup).
#
#   Full  — "Capital Call — Full: Notify Investors" (12 tasks, including a CFO sign-off with no approvers yet)
#   Light — "Capital Call — Light: Record Only" (4 tasks)
#   Rules — imported calls (manual_generation) → Light, priority 10; every other call → Full, 100
#
# The step lists below are what the Capital Calls user guide documents task by task, so adding,
# renaming or removing one here means editing "Tracking a Call: the Journey Step Bar" in
# docs/user_guides/capital_calls_user_guide.md too (H14 — checked by UserGuideLint, not Cucumber).
# Worked examples H10, H14, E15, E25, X5 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
class CapitalCallJourneySetup < JourneySetup
  WORKFLOWABLE_TYPE = "CapitalCall".freeze
  KEY_PREFIX = "capital_call.".freeze
  LABEL = "capital call journeys".freeze
  RECORD = "call".freeze # what the setup button's messages call one record
  FULL_KEY = "capital_call_full".freeze
  LIGHT_KEY = "capital_call_light".freeze
  FULL_NAME = "Capital Call — Full: Notify Investors".freeze
  LIGHT_NAME = "Capital Call — Light: Record Only".freeze
  DESCRIPTION = "Tracks each capital call from remittances to unit allocation. Seeded by CapHive; " \
                "admins can add approval steps or remove tasks.".freeze

  # [name, kind, check, skip, unlocks, description]
  FULL_STEPS = [
    ["Create remittances", "system", "create_remittances", nil, nil,
     "Every investor in the call's closes has a remittance (or the remittance upload has finished)."],
    ["Add call notice template", "system", "add_call_notice_template", "notices_not_applicable", nil,
     "The fund has a call notice template to generate notices from."],
    ["Generate notices", "system", "generate_notices", "notices_not_applicable", nil,
     "Every investor who is emailed has a generated call notice. Unverified KYC blocks a notice."],
    ["Approve notices", "system", "approve_notices", "notices_not_applicable", nil,
     "Every generated call notice has been approved on the Documents screen."],
    ["Review email", "acknowledge", "review_email", "review_not_needed", nil,
     "Someone has read the call email investors will receive and clicked Mark reviewed."],
    ["Check preview", "acknowledge", "check_preview", "review_not_needed", nil,
     "Someone has previewed the email with a notice attached and clicked Mark reviewed."],
    ["CFO sign-off", "human", nil, nil, nil,
     "The CFO signs off before the call is approved. Pick the approver(s) by editing this step."],
    ["Approve call", "system", "approve_call", "imported", "Approve",
     "The call is approved. Not applicable to imported calls."],
    ["Send notices", "system", "send_notices", "notices_not_applicable", "Send Notification",
     "Every investor who should be emailed has been sent the call notice."],
    ["Collect payments", "system", "collect_payments", nil, nil,
     "Everything called, including other fees, has been collected."],
    ["Verify remittances", "system", "verify_remittances", nil, nil,
     "Every remittance has been verified."],
    ["Allocate units", "system", "allocate_units", "no_unit_prices", nil,
     "Every verified remittance has fund units. Not applicable when the call has no unit prices."]
  ].freeze
  LIGHT_STEP_NAMES = ["Create remittances", "Collect payments", "Verify remittances", "Allocate units"].freeze

  # Imported calls get Light
  APPROVE_STEP_NAME = "Approve call".freeze
  LIGHT_CONDITIONS = [{ "attribute" => "manual_generation", "operator" => "eq", "value" => "true" }].freeze
end
