# The investor KYC journey: what JourneySetup seeds for KYCs (the seeding itself, idempotency and the
# dry run live in JourneySetup).
#
#   One template — "Investor KYC" (9 tasks, including a Compliance sign-off with no approvers yet)
#   One rule     — every new KYC → "Investor KYC", priority 100 (the default)
#
# No Light journey: a KYC the fund fills in itself skips "Send KYC form" (n/a), and an imported, already
# verified KYC is finished by the closing "Verify KYC" check. A company that wants a different journey
# for one KYC form type duplicates this template and adds a higher-priority rule for that form type;
# every other form type keeps this one (design Decision 13).
#
# The step list below is what the Investor KYC user guide documents task by task, so adding, renaming
# or removing one here means editing its journey section in docs/user_guides/investor_kyc_user_guide.md too.
# Worked examples H1, H2, E25 — openspec/changes/investor-kyc-journey/design.md#worked-examples
class InvestorKycJourneySetup < JourneySetup
  WORKFLOWABLE_TYPE = "InvestorKyc".freeze
  KEY_PREFIX = "investor_kyc.".freeze
  LABEL = "investor KYC journeys".freeze
  RECORD = "KYC".freeze # what the setup menu's messages call one record
  FULL_KEY = "investor_kyc_full".freeze
  FULL_NAME = "Investor KYC".freeze
  FULL_LABEL = "KYC".freeze
  DESCRIPTION = "Tracks each investor KYC from sending the form to verification. Seeded by CapHive; " \
                "admins can pick the Compliance sign-off approver, remove tasks, or duplicate it for one KYC form type.".freeze
  # KYCs are created by Angel Funds too (48 in production this year)
  ENTITY_TYPES = ["Investment Fund", "Angel Fund"].freeze
  SIGN_OFF_NAME = "Compliance sign-off".freeze
  SIGN_OFF_DESCRIPTION = "Compliance signs off before the KYC is verified. Pick the approver(s) by editing this step; " \
                         "until someone is picked it shows as not applicable.".freeze
  # The step the sign-off goes before when it is added to an older template
  APPROVE_STEP_NAME = "Verify KYC".freeze

  # [name, kind, check, skip, unlocks, description]
  FULL_STEPS = [
    ["Send KYC form", "system", "send_form", "filled_by_fund", nil,
     "The KYC form link has been emailed to the investor. Not applicable when the fund filled the KYC in itself."],
    ["Submit KYC", "system", "submit", nil, nil,
     "The investor submitted the KYC, or a fund user ticked \"I confirm all details provided are complete\"."],
    ["Upload required documents", "system", "upload_documents", "no_required_documents", nil,
     "Every document the company requires for this KYC type (settings list and required document fields) is uploaded."],
    ["Validate documents", "acknowledge", "validate_documents", nil, nil,
     "AI validation passed every answer, or someone checked the documents and clicked Mark reviewed."],
    ["Run AML screening", "system", "run_aml", "aml_off", nil,
     "An AML result exists. Not applicable when AML is not enabled for the company."],
    ["Clear AML match", "system", "clear_aml_match", "no_aml_match", nil,
     "A potential AML match was reviewed and overridden to no match. Not applicable when there is no match."],
    ["Review KYC", "acknowledge", "review_kyc", nil, nil,
     "Someone has checked the KYC details and clicked Mark reviewed."],
    ["Compliance sign-off", "human", nil, nil, nil,
     "Compliance signs off before the KYC is verified. Pick the approver(s) by editing this step."],
    ["Verify KYC", "system", "verify", nil, nil,
     "The KYC is verified. Verifying early marks any unfinished task before it \"Verified without this step\"."]
  ].freeze
end
